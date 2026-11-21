{ config, lib, pkgs, ... }:

# RomM: Weboberflaeche fuer die ROM-Sammlung (Cover, Infos, Spielen im Browser per EmulatorJS,
# Download auf andere Geraete). https://github.com/rommapp/romm  ->  http://10.0.0.5:8089
# Neue ROMs holt ROMarr (containers/romarr.nix) und legt sie in denselben Ordner.
#
# Bibliothek: ${roms} (Plattform-Ordner direkt darin, RomM "Structure A",
# im Container /romm/library/roms). Ordner heissen wie die RomM-Kuerzel (gb, gbc, gba, nds, 3ds,
# n64, nes, snes, dc, genesis, gamegear, sms, wii, wiiu, switch, ps4, wonderswan, xbox360 ...);
# abweichende Namen liessen sich in config.yml binden (system.platforms, auch in der Oberflaeche
# unter "Library Management").
#
# Erster Aufruf: Einrichtungsassistent legt den Admin an. Danach fuer ROMarr einen eigenen
# Benutzer "romarr" (Rolle Editor, darf scannen) anlegen.
#
# Metadaten: Hasheous ist an (ohne Konto). IGDB, ScreenScraper, RetroAchievements, SteamGridDB
# brauchen Zugaenge, die kommen in ${dataDir}/romm.env (erzeugt beim ersten Start, nur root):
#   sudo nano ${dataDir}/romm.env   danach   sudo systemctl restart docker-romm
let
  port = 8089;
  dataDir = "${config.nas.servicesDir}/romm";
  roms = "${config.nas.mediaDir}/Roms";
  uid = toString config.users.users.lmlzr.uid;
  gid = "989"; # Gruppe media
  network = "romm"; # eigenes Docker-Netz, damit RomM die Datenbank unter "romm-db" findet

  # Startwert, RomM schreibt die Datei selbst um (Einstellungen aus der Oberflaeche)
  # Die Plattform-Ordner heissen seit 2026-11-11 wie die RomM-Kuerzel, keine Zuordnung noetig.
  initialConfig = (pkgs.formats.yaml { }).generate "romm-config.yml" {
    exclude.platforms = [ "_Bios" "_Extras" ]; # _Extras: Spielstaende, Amiibo, DLC ohne Spiel
  };

  genSecrets = pkgs.writeShellScript "romm-secrets" ''
    set -eu
    umask 077
    install -d -m 0750 -o ${uid} -g ${gid} ${dataDir}
    rand() { ${pkgs.openssl}/bin/openssl rand -hex 32; }
    if [ ! -e ${dataDir}/db.env ]; then
      echo "MARIADB_PASSWORD=$(rand)" > ${dataDir}/db.env
      echo "MARIADB_ROOT_PASSWORD=$(rand)" >> ${dataDir}/db.env
    fi
    if [ ! -e ${dataDir}/romm.env ]; then
      pw=$(${pkgs.gnused}/bin/sed -n 's/^MARIADB_PASSWORD=//p' ${dataDir}/db.env)
      {
        echo "# RomM, siehe containers/romm.nix. Nach Aenderungen: sudo systemctl restart docker-romm"
        echo "DB_PASSWD=$pw"
        echo "ROMM_AUTH_SECRET_KEY=$(rand)"
        echo
        echo "# Metadaten-Anbieter: Zeile einkommentieren und eintragen"
        echo "#IGDB_CLIENT_ID="
        echo "#IGDB_CLIENT_SECRET="
        echo "#SCREENSCRAPER_USER="
        echo "#SCREENSCRAPER_PASSWORD="
        echo "#RETROACHIEVEMENTS_API_KEY="
        echo "#STEAMGRIDDB_API_KEY="
      } > ${dataDir}/romm.env
    fi
    chown root:root ${dataDir}/db.env ${dataDir}/romm.env
    chmod 600 ${dataDir}/db.env ${dataDir}/romm.env
  '';
in
{
  virtualisation.oci-containers = {
    backend = "docker";

    containers.romm-db = {
      image = "mariadb:11.8";
      volumes = [ "${dataDir}/db:/var/lib/mysql" ];
      environment = {
        MARIADB_DATABASE = "romm";
        MARIADB_USER = "romm";
        TZ = config.time.timeZone;
      };
      environmentFiles = [ "${dataDir}/db.env" ];
      extraOptions = [ "--network=${network}" ];
      autoStart = true;
    };

    containers.romm = {
      image = "rommapp/romm:5.4.1";
      ports = [ "${toString port}:8080" ];
      # Image-Benutzer romm hat uid 1000 (= lmlzr), Gruppe media fuer die Bibliothek
      user = "${uid}:${gid}";
      volumes = [
        "${dataDir}/resources:/romm/resources" # Cover, Screenshots
        "${dataDir}/redis:/redis-data"
        "${dataDir}/assets:/romm/assets" # Spielstaende, hochgeladene Saves
        "${dataDir}/config:/romm/config"
        "${roms}:/romm/library/roms"
      ];
      environment = {
        DB_HOST = "romm-db";
        DB_NAME = "romm";
        DB_USER = "romm";
        HASHEOUS_API_ENABLED = "true";
        SCAN_WORKERS = "2";
        WEB_SERVER_CONCURRENCY = "2";
        # Neue Dateien (von ROMarr oder von Hand) selbst einlesen, 5 min nach der letzten
        # Aenderung. ROMarr kann den Scan nicht ausloesen: "tasks.run" haben in RomM 5.4 nur
        # Admins, auch Editor nicht. inotify weckt die Platten nicht, nur der Scan selbst.
        ENABLE_RESCAN_ON_FILESYSTEM_CHANGE = "true";
        TZ = config.time.timeZone;
      };
      environmentFiles = [ "${dataDir}/romm.env" ];
      extraOptions = [ "--network=${network}" ];
      dependsOn = [ "romm-db" ];
      autoStart = true;
    };
  };

  systemd.services.romm-setup = {
    description = "RomM: Docker-Netz und Secrets anlegen";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    before = [ "docker-romm-db.service" "docker-romm.service" ];
    unitConfig.RequiresMountsFor = [ config.nas.servicesDir ];
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${genSecrets}
      docker network inspect ${network} >/dev/null 2>&1 || docker network create ${network}
    '';
  };

  systemd.services.docker-romm-db = {
    requires = [ "romm-setup.service" ];
    after = [ "romm-setup.service" ];
    preStart = ''
      install -d -m 0750 ${dataDir}/db
    '';
  };

  systemd.services.docker-romm = {
    requires = [ "romm-setup.service" ];
    after = [ "romm-setup.service" ];
    unitConfig.RequiresMountsFor = [ config.nas.servicesDir config.nas.mediaDir ];
    preStart = ''
      install -d -m 0750 -o ${uid} -g ${gid} ${dataDir}/resources ${dataDir}/redis \
        ${dataDir}/assets ${dataDir}/config
      if [ ! -e ${dataDir}/config/config.yml ]; then
        install -m 0640 -o ${uid} -g ${gid} ${initialConfig} ${dataDir}/config/config.yml
      fi
    '';
  };

  networking.firewall.interfaces.${config.nas.lanInterface}.allowedTCPPorts = [ port ];
}
