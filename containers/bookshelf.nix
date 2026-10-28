{ config, lib, pkgs, ... }:

# Bookshelf: Buecher-Gegenstueck zu Sonarr/Radarr (Weiterentwicklung des eingestellten Readarr,
# https://github.com/pennydreadful/bookshelf). Variante "hardcover": Buchdaten von hardcover.app,
# weil die Datenquelle von Readarr abgeschaltet ist. Weboberflaeche: http://10.0.0.5:8787
#
# Die Mediathek liegt im Container unter demselben Pfad wie auf dem Host (/mnt/tank/media), damit
# Bookshelf die Downloads von qBittorrent ohne Pfad-Umrechnung findet.
# qBittorrent als Download-Client: Host 10.0.0.5, Port 8080, Kategorie "books".
# Prowlarr: unter Apps als "Readarr" mit http://10.0.0.5:8787 eintragen (gleiche API).
let
  cfg = config.nas;
  port = 8787;
  dataDir = "${cfg.servicesDir}/bookshelf";
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers.bookshelf = {
      image = "ghcr.io/pennydreadful/bookshelf:hardcover-v0.4.21.182";
      ports = [ "${toString port}:8787" ];
      volumes = [
        "${dataDir}:/config"
        "${cfg.mediaDir}:${cfg.mediaDir}" # Books, Audiobooks, downloads
      ];
      environment = {
        PUID = toString config.users.users.lmlzr.uid;
        PGID = "989"; # Gruppe media
        UMASK = "002";
        TZ = config.time.timeZone;
      };
      autoStart = true;
    };
  };

  systemd.services.docker-bookshelf = {
    unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir ];
    preStart = ''
      install -d -m 0750 -o ${toString config.users.users.lmlzr.uid} -g 989 ${dataDir}
    '';
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
