{ config, lib, pkgs, ... }:

# Tdarr: bearbeitet die Mediathek nach Regeln (Plugins/Flows), hier vor allem um Ton- und
# Untertitelspuren in anderen Sprachen als Deutsch/Englisch zu entfernen (Remux, ohne neu zu
# kodieren) und grosse Dateien per NVENC nach HEVC umzuwandeln. Server, Weboberflaeche und ein
# Node in einem Container. http://10.0.0.5:8265
#
# Einrichten in der Oberflaeche:
#   1. Libraries -> Bibliothek anlegen, Source z. B. /mnt/tank/media/TV (gleicher Pfad wie auf
#      dem Host), Transcode cache /temp.
#      "Folder watch" AUS und "Scan on start" AUS: sonst weckt Tdarr die Platten staendig
#      (siehe hd-idle). Lieber von Hand scannen oder nachts per "Schedule".
#   2. Transcode Options -> Classic Plugins, nur diese beiden:
#        Migz Clean audio streams  (language: ger,eng   commentary: false  tag_language: leer)
#        Migz Clean subtitle streams (language: ger,eng   commentary: false)
#      Spuren ohne Sprache ("und") bleiben, Ton wird nie komplett entfernt.
#   3. Erst eine Probe-Bibliothek mit einem einzelnen Ordner anlegen und das Ergebnis pruefen.
# Danach in Sonarr/Radarr "Rescan" (die Dateien bleiben unter demselben Namen).
#
# Nur im Heimnetz erreichbar. Login ist in der Oberflaeche eingeschaltet (auth: true in
# configs/Tdarr_Server_Config.json); das Homepage-Widget braucht dann einen API-Key
# (Tdarr -> API Keys, auf vmdocker als TDARR_KEY in ~/homepage-keys.env).
let
  cfg = config.nas;
  port = 8265; # Weboberflaeche
  serverPort = 8266; # Nodes <-> Server (nur intern, der Node laeuft im selben Container)
  dataDir = "${cfg.servicesDir}/tdarr";
  # Zwischendateien (bis Filmgroesse) auf fast/incomplete: keine Snapshots, kein naechtliches Backup.
  # In fast/services blieb jede geloeschte Zwischendatei wochenlang in den Snapshots liegen
  # (wie bei ARM/MakeMKV). Quota 600G teilen sich qBittorrent, ARM, MakeMKV und Tdarr.
  cache = if cfg.fastPool != null then "/mnt/${cfg.fastPool}/incomplete/tdarr" else "${dataDir}/cache";
  uid = toString config.users.users.lmlzr.uid;
  gid = "989"; # Gruppe media, Bibliothek gehoert root:media (2775/664)
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers.tdarr = {
      image = "ghcr.io/haveagitgat/tdarr:latest";
      ports = [ "${toString port}:8265" ];
      volumes = [
        "${dataDir}/server:/app/server"
        "${dataDir}/configs:/app/configs"
        "${dataDir}/logs:/app/logs"
        "${cache}:/temp"
        "${cfg.mediaDir}/TV:${cfg.mediaDir}/TV"
        "${cfg.mediaDir}/Movies:${cfg.mediaDir}/Movies"
      ];
      environment = {
        # Container startet als root und wechselt per PUID/PGID (kein "user =")
        PUID = uid;
        PGID = gid;
        UMASK_SET = "002"; # neue Dateien 664 wie der Rest der Bibliothek
        TZ = config.time.timeZone;
        serverIP = "0.0.0.0";
        serverPort = toString serverPort;
        webUIPort = "8265";
        internalNode = "true";
        inContainer = "true";
        ffmpegVersion = "7";
        nodeName = "neotokyo";
      };
      # NVENC (Quadro P400, teilt sie sich mit Jellyfin/ErsatzTV; Quadro hat kein Sitzungslimit).
      # Pascal: H.264/HEVC ja, kein AV1, HEVC ohne B-Frames (braucht mehr Bitrate als x265).
      extraOptions = [ "--device=nvidia.com/gpu=all" ];
      autoStart = true;
    };
  };

  systemd.services.docker-tdarr = {
    unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir cache ];
    preStart = ''
      install -d -m 0750 -o ${uid} -g ${gid} ${dataDir} ${dataDir}/server ${dataDir}/configs \
        ${dataDir}/logs ${cache}
    '';
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
