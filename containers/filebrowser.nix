{ config, lib, pkgs, ... }:

# FileBrowser Quantum: Web-Dateimanager fuer die Freigabe auf tank, mit Freigabe-Links
# (Ablaufdatum, Passwort, Download-Limit) fuer andere Leute.
# https://github.com/gtsteffaniak/filebrowser
#   Heimnetz:  http://10.0.0.5:8088
#   von aussen: https://files.<DOMAIN> (nginx auf dem VPS, siehe vps/nginx-homelab.conf)
#
# Inhalt: /mnt/tank/share/lmlzr (normale Dateien, ZFS-Snapshots und Backup greifen weiter).
# Der Ordner von dbglas ist privat (0700) und deshalb nicht dabei.
#
# Anmeldung: Benutzer lmlzr, das Passwort erzeugt der erste Start und steht in admin.env
# (nur root lesbar): sudo cat /mnt/fast/services/filebrowser/admin.env
# Es wird bei jedem Start gesetzt; aendern also in admin.env, nicht in der Oberflaeche.
let
  port = 8088;
  dataDir = "${config.nas.servicesDir}/filebrowser"; # Datenbank, Vorschaubilder, admin.env
  share = "${config.nas.pool}/share/lmlzr";
  shareDir = "/mnt/${share}";
  uid = toString config.users.users.lmlzr.uid;
  gid = toString config.users.groups.users.gid;

  settings = {
    server = {
      sources = [{
        path = "/srv/lmlzr";
        name = "Dateien";
        config.defaultEnabled = true;
      }];
      cacheDir = "/home/filebrowser/data/tmp";
      cacheDirCleanup = true;
      database.path = "/home/filebrowser/data/database.sqlite";
    };
    # Schluessel wie in Version 2.0.2 (die aktuelle Doku auf GitHub beschreibt eine neuere)
    auth = {
      tokenExpirationHours = 168; # eine Woche angemeldet bleiben
      adminUsername = "lmlzr";
      methods.password = {
        enabled = true;
        minLength = 10;
        signup = false;
      };
    };
    http = {
      port = 80;
      # Freigabe-Links zeigen auf die oeffentliche Adresse (Domain aus modules/private.nix)
      externalUrl = "https://files.${config.nas.private.DOMAIN}";
      # Anfragen von aussen kommen ueber nginx auf dem VPS (WireGuard, Absender 10.10.0.1)
      trustProxyHeaders = true;
    };
    frontend.name = "neotokyo Dateien";
  };
  configFile = (pkgs.formats.yaml { }).generate "filebrowser-config.yaml" settings;
in
{
  virtualisation.oci-containers = {
    backend = "docker";

    containers.filebrowser = {
      image = "gtstef/filebrowser:2.0.2-stable";
      ports = [ "${toString port}:80" ];
      user = "${uid}:${gid}"; # lmlzr:users, wie die Dateien in der Freigabe
      volumes = [
        "${dataDir}:/home/filebrowser/data"
        "${configFile}:/home/filebrowser/config.yaml:ro"
        "${shareDir}:/srv/lmlzr"
      ];
      environment = {
        FILEBROWSER_CONFIG = "/home/filebrowser/config.yaml";
        FILEBROWSER_DATABASE_PATH = "/home/filebrowser/data/database.sqlite";
        TZ = config.time.timeZone;
      };
      # FILEBROWSER_ADMIN_PASSWORD (erzeugt im preStart, nicht im Repo)
      environmentFiles = [ "${dataDir}/admin.env" ];
      autoStart = true;
    };
  };

  systemd.services.docker-filebrowser = {
    unitConfig.RequiresMountsFor = [ dataDir shareDir ];
    preStart = ''
      install -d -m 0750 -o ${uid} -g ${gid} ${dataDir}
      if [ ! -s ${dataDir}/admin.env ]; then
        umask 077
        echo "FILEBROWSER_ADMIN_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 18 | tr -d '/+=')" > ${dataDir}/admin.env
      fi
      chown root:root ${dataDir}/admin.env
      chmod 600 ${dataDir}/admin.env
    '';
  };

  networking.firewall.interfaces.${config.nas.lanInterface}.allowedTCPPorts = [ port ];
}
