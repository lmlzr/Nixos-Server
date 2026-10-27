{ config, lib, pkgs, ... }:

# HandBrake (mit NVENC ueber die Quadro P400) und MakeMKV, beide mit Weboberflaeche im Browser:
#   HandBrake  http://10.0.0.5:5800
#   MakeMKV    http://10.0.0.5:5801
# Ordner (SMB-Freigabe "media"):
#   /mnt/tank/media/Transcode/MakeMKV           Ausgabe von MakeMKV
#   /mnt/tank/media/Transcode/HandBrake-Watch   was hier landet, kodiert HandBrake automatisch
#   /mnt/tank/media/Transcode/HandBrake-Output  Ergebnis
# Die ganze Mediathek liegt in beiden schreibbar unter /storage (Ergebnis direkt in Movies/TV
# speichern, ISOs aus /storage/ISOs rippen).
# Kein optisches Laufwerk eingebaut: MakeMKV verarbeitet ISO-Dateien/Disc-Ordner. Fuer ein
# (USB-)Laufwerk spaeter "--device=/dev/sr0" und das passende /dev/sgN durchreichen.
let
  cfg = config.nas;
  transcode = "${cfg.mediaDir}/Transcode";
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
      environment = common;
      extraOptions = [ "--device=nvidia.com/gpu=all" ];
      autoStart = true;
    };

    containers.makemkv = {
      image = "jlesage/makemkv:v26.09.2";
      ports = [ "5801:5800" ];
      volumes = [
        "${cfg.servicesDir}/makemkv:/config:rw"
        "${cfg.mediaDir}:/storage:rw" # schreibbar: direkt nach Movies/TV rippen
        "${transcode}/MakeMKV:/output:rw"
      ];
      environment = common; # MakeMKV-Beta-Schluessel holt das Image selbst
      autoStart = true;
    };
  };

  systemd.services = lib.genAttrs [ "docker-handbrake" "docker-makemkv" ] (name: {
    unitConfig.RequiresMountsFor = [ cfg.mediaDir cfg.servicesDir ];
    preStart = ''
      install -d -m 0750 -o ${common.USER_ID} -g ${common.GROUP_ID} ${cfg.servicesDir}/${lib.removePrefix "docker-" name}
    '';
  });

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ 5800 5801 ];
}
