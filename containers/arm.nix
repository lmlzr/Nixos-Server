{ config, lib, pkgs, ... }:

# Automatic Ripping Machine (ARM): Disc einlegen -> erkennen (OMDb/TMDb) -> mit MakeMKV rippen
# -> mit HandBrake (NVENC) umwandeln -> sauber benannt ablegen -> auswerfen.
# Weboberflaeche: http://10.0.0.5:8095 (8080 belegt qBittorrent).
#
# VORBEREITET, AUS: das optische Laufwerk ist noch nicht eingebaut. Einschalten mit
# `nas.arm.enable = true;` sobald /dev/sr0 existiert (lsblk, `ls /dev/sr*`), dann Rebuild.
# Danach in der ARM-Oberflaeche einrichten (Settings): HandBrake-Vorlagen auf NVENC, Zielordner.
# OMDb-API-Schluessel (https://www.omdbapi.com/apikey.aspx) liegt in /etc/secrets/arm-omdb-key
# (nur der Key, eine Zeile) und wird bei jedem Start in arm.yaml (OMDB_API_KEY) eingetragen.
#
# ARM braucht --privileged: es startet im Container einen eigenen udev, der das Einlegen einer
# Disc erkennt, und greift auf /dev/srN und das zugehoerige /dev/sgN zu.
let
  cfg = config.nas;
  armDir = "${cfg.servicesDir}/arm";
  media = "${cfg.mediaDir}/Transcode/ARM";
in
{
  options.nas.arm.enable = lib.mkEnableOption "Automatic Ripping Machine (braucht ein optisches Laufwerk)";

  config = lib.mkIf cfg.arm.enable {
    virtualisation.oci-containers = {
      backend = "docker";
      containers.arm = {
        image = "automaticrippingmachine/automatic-ripping-machine:2.24.4";
        ports = [ "8095:8080" ];
        volumes = [
          "${armDir}/home:/home/arm"
          "${armDir}/logs:/home/arm/logs"
          "${armDir}/config:/etc/arm/config"
          "${media}:/home/arm/media" # raw/, transcode/, completed/
          "${cfg.mediaDir}/Music:/home/arm/music"
        ];
        environment = {
          ARM_UID = toString config.users.users.lmlzr.uid;
          ARM_GID = "989"; # Gruppe media
          TZ = config.time.timeZone;
        };
        extraOptions = [
          "--privileged"
          "--device=nvidia.com/gpu=all" # NVENC fuer HandBrake in ARM
        ];
        autoStart = true;
      };
    };

    systemd.services.docker-arm = {
      unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir ];
      preStart = ''
        for d in ${armDir}/home ${armDir}/logs ${armDir}/config ${media}; do
          install -d -m 2775 -o ${toString config.users.users.lmlzr.uid} -g 989 "$d"
        done
      '';
      # arm.yaml legt der Container beim ersten Start an; danach den OMDb-Key eintragen.
      # ARM liest die Datei bei jedem Rip neu, ein Neustart ist nicht noetig.
      postStart = ''
        key=/etc/secrets/arm-omdb-key
        conf=${armDir}/config/arm.yaml
        [ -s "$key" ] || exit 0
        for _ in $(seq 60); do [ -f "$conf" ] && break; sleep 2; done
        [ -f "$conf" ] || exit 0
        k=$(tr -d '[:space:]' < "$key")
        ${pkgs.gnused}/bin/sed -i "s|^OMDB_API_KEY:.*|OMDB_API_KEY: \"$k\"|" "$conf"
      '';
    };

    networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ 8095 ];
  };
}
