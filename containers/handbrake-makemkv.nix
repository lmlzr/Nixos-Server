{ config, lib, pkgs, ... }:

# HandBrake (mit NVENC ueber die Quadro P400) und MakeMKV, beide mit Weboberflaeche im Browser:
#   HandBrake  http://10.0.0.5:5800
#   MakeMKV    http://10.0.0.5:5801
# Ordner (SMB-Freigabe "media"):
#   /mnt/tank/media/Transcode/MakeMKV           Ausgabe von MakeMKV (fertige Rips, siehe unten)
#   /mnt/tank/media/Transcode/HandBrake-Watch   was hier landet, kodiert HandBrake automatisch
#   /mnt/tank/media/Transcode/HandBrake-Output  Ergebnis
# Die ganze Mediathek liegt in beiden schreibbar unter /storage (Ergebnis direkt in Movies/TV
# speichern, ISOs aus /storage/ISOs rippen).
# MakeMKV verarbeitet ISO-Dateien/Disc-Ordner. Das Blu-ray-Laufwerk bekommt es absichtlich nicht:
# das gehoert ARM allein (2026-11-01 liefen beide makemkvcon auf derselben Disc auf Volllast fest).
let
  cfg = config.nas;
  transcode = "${cfg.mediaDir}/Transcode";
  # MakeMKV rippt auf die NVMe (fast/incomplete, ohne Snapshots), makemkv-move schiebt fertige
  # Dateien nach Transcode/MakeMKV auf tank. Die HDDs laufen so nur kurz beim Verschieben.
  # Ohne fastPool direkt auf tank wie frueher.
  makemkvOut = "${transcode}/MakeMKV";
  makemkvWork = if cfg.fastPool != null then "/mnt/${cfg.fastPool}/incomplete/makemkv" else makemkvOut;
  # Fertig = seit 5 min unveraendert und von keinem Prozess mehr offen (MakeMKV schreibt
  # laufend, eine abgebrochene Datei bleibt offen bis zum Abbruch). Unterordner bleiben erhalten.
  # Kontrolle: journalctl -u makemkv-move
  makemkvMove = {
    description = "Fertige MakeMKV-Rips von der NVMe nach tank verschieben";
    unitConfig.RequiresMountsFor = [ makemkvWork cfg.mediaDir ];
    path = [ pkgs.coreutils pkgs.findutils pkgs.psmisc ];
    serviceConfig = {
      Type = "oneshot";
      User = "lmlzr";
      Group = "media";
      UMask = "0002";
    };
    script = ''
      cd ${makemkvWork}
      find . -type f -mmin +5 -print0 | while IFS= read -r -d "" f; do
        fuser -s "$f" 2>/dev/null && continue
        install -d -m 2775 "${makemkvOut}/$(dirname "$f")"
        # erst kopieren, dann loeschen; .part schuetzt vor halben Dateien in tank
        cp --preserve=timestamps "$f" "${makemkvOut}/$f.part" \
          && mv "${makemkvOut}/$f.part" "${makemkvOut}/$f" && rm "$f" \
          && echo "verschoben: $f"
      done
      find . -mindepth 1 -type d -empty -mmin +5 -delete
    '';
  };
  common = {
    USER_ID = toString config.users.users.lmlzr.uid;
    GROUP_ID = "989"; # Gruppe media (getent group media)
    UMASK = "002";
    TZ = config.time.timeZone;
    KEEP_APP_RUNNING = "1";
  };
in
{
  # GPU in Containern per CDI: --device=nvidia.com/gpu=all
  hardware.nvidia-container-toolkit.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";

    containers.handbrake = {
      # jlesage/handbrake kann kein NVENC; dieses Image baut darauf auf (gleiche Oberflaeche)
      image = "zocker160/handbrake-nvenc:110x";
      ports = [ "5800:5800" ];
      volumes = [
        "${cfg.servicesDir}/handbrake:/config:rw"
        "${cfg.mediaDir}:/storage:rw" # schreibbar: Ergebnis direkt in die Bibliothek speichern
        "${transcode}/HandBrake-Watch:/watch:rw"
        "${transcode}/HandBrake-Output:/output:rw"
      ];
      environment = common // {
        # Watch-Ordner: sonst "Very Fast 1080p30" (x264 auf der CPU) und MP4
        AUTOMATED_CONVERSION_PRESET = "H.265 NVENC 1080p";
        AUTOMATED_CONVERSION_FORMAT = "mkv";
        # Dekodieren auf der GPU (NVDEC): bei HD-Quellen (H.264/HEVC) ~40 % schneller, bei
        # DVD-MPEG-2 kein Vorteil (getestet 2026-11-04). In der Oberflaeche gilt das nicht,
        # dort pro Auftrag einstellen. ARMs HandBrake ist ohne NVDEC gebaut.
        AUTOMATED_CONVERSION_HANDBRAKE_CUSTOM_ARGS = "--enable-hw-decoding nvdec";
      };
      extraOptions = [ "--device=nvidia.com/gpu=all" ];
      autoStart = true;
    };

    containers.makemkv = {
      image = "jlesage/makemkv:v26.09.2";
      ports = [ "5801:5800" ];
      volumes = [
        "${cfg.servicesDir}/makemkv:/config:rw"
        "${cfg.mediaDir}:/storage:rw" # schreibbar: direkt nach Movies/TV rippen
        "${makemkvWork}:/output:rw"
      ];
      environment = common; # MakeMKV-Beta-Schluessel holt das Image selbst
      autoStart = true;
    };
  };

  systemd.services = lib.mkMerge [
    (lib.genAttrs [ "docker-handbrake" "docker-makemkv" ] (name: {
      unitConfig.RequiresMountsFor = [ cfg.mediaDir cfg.servicesDir ];
      preStart = ''
        install -d -m 0750 -o ${common.USER_ID} -g ${common.GROUP_ID} ${cfg.servicesDir}/${lib.removePrefix "docker-" name}
      '';
    }))
    {
      docker-makemkv.unitConfig.RequiresMountsFor = [ makemkvWork ];
      docker-makemkv.preStart = lib.mkAfter ''
        install -d -m 2775 -o ${common.USER_ID} -g ${common.GROUP_ID} ${makemkvWork} ${makemkvOut}
      '';
      makemkv-move = lib.mkIf (makemkvWork != makemkvOut) makemkvMove;
    }
  ];

  systemd.timers.makemkv-move = lib.mkIf (makemkvWork != makemkvOut) {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "5min";
    };
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ 5800 5801 ];
}
