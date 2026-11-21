{ config, lib, pkgs, ... }:

# ROMarr: "*arr fuer Spiele/ROMs". Sucht ueber Prowlarr, laedt mit qBittorrent, prueft die
# Datei gegen No-Intro/Redump-Pruefsummen und legt sie in die RomM-Bibliothek, danach Rescan in RomM.
# https://github.com/BlizzHacker/romarr  ->  http://10.0.0.5:6868 (nur im Heimnetz)
#
# Host-Netz: erreicht Prowlarr (127.0.0.1:9696), RomM (127.0.0.1:8089) und qBittorrent im
# VPN-Namespace (192.168.15.1:8080) wie Sonarr/Radarr.
# Anmeldung und API-Key stehen in ${dataDir}/secrets.env (beim ersten Start erzeugt).
# Die Verbindungen (Prowlarr-Key, RomM-Benutzer, qBittorrent-Login) werden in der
# Oberflaeche unter Settings eingetragen; die Umgebungsvariablen unten gelten nur beim ersten Start.
let
  port = 6868;
  dataDir = "${config.nas.servicesDir}/romarr";
  roms = "${config.nas.mediaDir}/Roms";
  downloads = "${config.nas.mediaDir}/downloads"; # qBittorrent DefaultSavePath, gleicher Pfad
  uid = toString config.users.users.lmlzr.uid;
  gid = "989"; # Gruppe media
in
{
  virtualisation.oci-containers = {
    backend = "docker";

    containers.romarr = {
      image = "ghcr.io/blizzhacker/romarr:1.8.1";
      volumes = [
        "${dataDir}/config:/config"
        "${roms}:/roms" # = /romm/library/roms in RomM (Structure A: <Plattform>/<ROM>)
        "${downloads}:${downloads}" # gleiches Dataset wie die Bibliothek -> Hardlinks moeglich
      ];
      environment = {
        PUID = uid;
        PGID = gid;
        UMASK = "002";
        TZ = config.time.timeZone;
        LIBRARY_KIND = "romm";
        LIBRARY_URL = "http://127.0.0.1:8089";
        LIBRARY_PATH = "/roms";
        PROWLARR_URL = "http://127.0.0.1:9696";
        QBITTORRENT_URL = "http://192.168.15.1:8080";
        QBITTORRENT_CATEGORY = "romarr";
        LOG_LEVEL = "INFO";
      };
      # ROMARR_PASSWORD, ROMARR_API_KEY (erzeugt im romarr-secrets, nicht im Repo)
      environmentFiles = [ "${dataDir}/secrets.env" ];
      extraOptions = [ "--network=host" ];
      autoStart = true;
    };
  };

  systemd.services.docker-romarr = {
    unitConfig.RequiresMountsFor = [ config.nas.servicesDir config.nas.mediaDir ];
    preStart = ''
      install -d -m 0750 -o ${uid} -g ${gid} ${dataDir} ${dataDir}/config
      if [ ! -s ${dataDir}/secrets.env ]; then
        umask 077
        {
          echo "ROMARR_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 18 | tr -d '/+=')"
          echo "ROMARR_API_KEY=$(${pkgs.openssl}/bin/openssl rand -hex 16)"
        } > ${dataDir}/secrets.env
      fi
      chown ${uid}:${gid} ${dataDir}/secrets.env
      chmod 600 ${dataDir}/secrets.env
    '';
  };

  networking.firewall.interfaces.${config.nas.lanInterface}.allowedTCPPorts = [ port ];
}
