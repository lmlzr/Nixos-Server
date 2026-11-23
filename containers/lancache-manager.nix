{ config, pkgs, ... }:

# LANCache Manager: Dashboard fuer den Lancache mit Vorladen (Prefill) im Browser
# fuer Steam, Epic, Battle.net, Riot und Xbox, von Hand oder nach Zeitplan.
# https://github.com/regix1/lancache-manager  ->  http://10.0.0.5:8087 (nur im Heimnetz)
#
# Ersetzt seit 2026-11-09 das alte Dashboard (imahmud1/lancache-dashboard). Steam-Prefill laeuft seit
# 2026-11-23 nur noch ueber die Schedules hier (steam-lancache-prefill.nix ist nicht mehr importiert).
#
# Erster Aufruf: Einrichtungsseite (Datenbank-Passwort, Anmeldeart). Benutzer + Passwort waehlen,
# NICHT "ohne Anmeldung": der Manager hat den Docker-Socket (= praktisch root auf neotokyo).
# API-Key zur Wiederherstellung: docker exec lancache-manager cat /data/security/api_key.txt
#
# Vorladen: der Manager startet dafuer eigene Container (ghcr.io/regix1/*-prefill-daemon) ueber
# den Docker-Socket; die laden ueber die Lancache-IP, damit der Cache gefuellt wird.
let
  port = 8087;
  dataDir = "${config.nas.servicesDir}/lancache-manager"; # Datenbank (PostgreSQL), Bilder, Prefill
  logDir = config.services.lancache.logPrefix;
  cacheDir = config.nas.lancacheDir;
in
{
  virtualisation.oci-containers = {
    backend = "docker";

    containers.lancache-manager = {
      # :dev (1.10.7) statt :latest (1.10.6): die Prefill-Daemons sind fest auf :latest und
      # verlangen seit Ende Oktober Protokoll v2, das 1.10.6 nicht kann. Zurueck auf :latest,
      # sobald 1.10.7+ released ist. Backup von 1.10.6: ${dataDir}/backup-1.10.6
      image = "ghcr.io/regix1/lancache-manager:dev";
      ports = [ "${toString port}:80" ];
      volumes = [
        "${dataDir}:/data"
        # Log schreibbar: der Manager entfernt Eintraege (z. B. beim Loeschen eines Spiels aus dem
        # Cache) und schreibt die Datei dann neu; nginx muss sie danach neu oeffnen (--pid=host)
        "${logDir}:/logs"
        # Cache schreibbar: Spiele/Dienste/kaputte Dateien aus dem Cache loeschen (Manager laeuft
        # als nginx 60:60, dem der Cache gehoert)
        "${cacheDir}:/cache"
        "/var/run/docker.sock:/var/run/docker.sock"
      ];
      environment = {
        # Log und Cache gehoeren nginx (60:60, Ordner 0750)
        PUID = "60";
        PGID = "60";
        TZ = config.time.timeZone;
        LanCache__LogPath = "/logs/access.log";
        LanCache__CachePath = "/cache";
        # Prefill direkt ueber die Lancache-IP statt ueber DNS
        Prefill__LancacheIp = "10.0.0.5";
        # Log-Rotation macht logrotate (services/lancache.nix). Der Manager sucht nginx in
        # Docker-Containern, findet dabei die Web-UI von makemkv und bricht ab.
        NginxLogRotation__Enabled = "false";
      };
      # nginx laeuft direkt in NixOS: Host-PIDs sehen, damit der Manager nginx nach dem Umschreiben
      # des Logs ein "reopen" schicken kann (CAP_KILL hat der Container standardmaessig).
      # Ohne das schreibt nginx weiter in die geloeschte alte Datei.
      extraOptions = [ "--pid=host" ];
      autoStart = true;
    };
  };

  systemd.services.docker-lancache-manager = {
    unitConfig.RequiresMountsFor = [ dataDir cacheDir ];
    preStart = ''
      mkdir -p ${dataDir}
    '';
  };

  # nur im Heimnetz
  networking.firewall.interfaces.${config.nas.lanInterface}.allowedTCPPorts = [ port ];
}
