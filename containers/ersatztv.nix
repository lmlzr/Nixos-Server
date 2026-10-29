{ config, lib, pkgs, ... }:

# ErsatzTV: eigene "Fernsehsender" aus der Mediathek (z. B. Doctor Who rund um die Uhr,
# zufaellige Folgen), die Jellyfin als Live TV zeigt. http://10.0.0.5:8409
#
# Einrichten in ErsatzTV:
#   1. Media Sources -> Jellyfin: Adresse http://10.0.0.5:8096 und einen Jellyfin-API-Key
#      (Jellyfin: Dashboard -> API-Schluessel), dann Bibliotheken synchronisieren.
#      Die Mediathek ist unter denselben Pfaden eingehaengt wie bei Jellyfin (auch /data/...),
#      Path Replacements sind also nicht noetig. API-Key-Anmeldung: siehe services/jellyfin.nix.
#   2. Settings -> FFmpeg Profiles: Hardware Acceleration "Nvenc" (Quadro P400).
#   3. Lists -> Collections (z. B. alle Doctor-Who-Folgen), Schedules (Playback Order "Shuffle"),
#      Channels anlegen.
# In Jellyfin (Dashboard -> Live TV):
#   Tuner:  M3U   http://10.0.0.5:8409/iptv/channels.m3u
#   Guide:  XMLTV http://10.0.0.5:8409/iptv/xmltv.xml
let
  cfg = config.nas;
  port = 8409;
  dataDir = "${cfg.servicesDir}/ersatztv";
  uid = toString config.users.users.lmlzr.uid;
  gid = "989"; # Gruppe media
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers.ersatztv = {
      image = "ghcr.io/ersatztv/ersatztv:v26.2.0";
      ports = [ "${toString port}:8409" ];
      volumes = [
        "${dataDir}/config:/config"
        "${dataDir}/transcode:/transcode" # HLS-Segmente der laufenden Sender (NVMe)
        "${cfg.mediaDir}:${cfg.mediaDir}:ro" # gleicher Pfad wie in Jellyfin
        # Bibliotheken aus dem alten Docker-Jellyfin melden /data/... (siehe services/jellyfin.nix)
        "${cfg.mediaDir}/TV:/data/tvshows:ro"
        "${cfg.mediaDir}/Movies:/data/movies:ro"
        "${cfg.mediaDir}/Music:/data/music:ro"
        "${cfg.mediaDir}/Books:/data/Books:ro"
      ];
      environment.TZ = config.time.timeZone;
      user = "${uid}:${gid}";
      extraOptions = [ "--device=nvidia.com/gpu=all" ];
      autoStart = true;
    };
  };

  systemd.services.docker-ersatztv = {
    unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir ];
    preStart = ''
      install -d -m 0750 -o ${uid} -g ${gid} ${dataDir} ${dataDir}/config ${dataDir}/transcode
    '';
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
