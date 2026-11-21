{ config, lib, pkgs, ... }:

# Automatic Ripping Machine (ARM): Disc einlegen -> erkennen (OMDb/TMDb) -> mit MakeMKV rippen
# -> mit HandBrake (NVENC) umwandeln -> sauber benannt ablegen -> auswerfen.
# Weboberflaeche: http://10.0.0.5:8095 (8080 belegt qBittorrent).
#
# Laufwerk: LG BH08LS20 (/dev/sr0, /dev/sg0), SATA. Blu-ray und DVD, kein 4K-UHD.
# Schalter: `nas.arm.enable` in configuration.nix.
# OMDb-API-Schluessel (https://www.omdbapi.com/apikey.aspx) liegt in /etc/secrets/arm-omdb-key
# (nur der Key, eine Zeile). Er wird bei jedem Start in arm.yaml (OMDB_API_KEY) eingetragen,
# ebenso die NVENC-Vorlagen und die Tonspur-Sprachen unten (Aenderungen daran in der
# ARM-Oberflaeche gehen beim naechsten Start verloren).
#
# ARM braucht --privileged: es startet im Container einen eigenen udev, der das Einlegen einer
# Disc erkennt, und greift auf /dev/srN und das zugehoerige /dev/sgN zu.
# Das start_udev.sh des Images ist ersetzt: das Original ruft `udevadm trigger --action=add` auf.
# Im privilegierten Container trifft das alle Geraete des Hosts, der startet darauf den
# Nvidia-CDI-Dienst neu und Docker (Requires=) stoppt mit - alle Container fallen aus.
let
  startUdev = pkgs.writeScript "arm-start-udev" ''
    #!/bin/sh
    mkdir -p /run/udev
    /lib/systemd/systemd-udevd --daemon
  '';
  # Ton und Untertitel: Deutsch, Englisch, Italienisch, Ton unveraendert, Untertitel nie eingebrannt.
  # Das NVENC-Preset waere Stereo-AAC und MP4 (das kann PGS-Untertitel nicht als Spur speichern).
  # --aencoder copy kopiert nur mit --audio-copy-mask, sonst wird trotzdem nach Stereo umgewandelt.
  hbArgs = lib.concatStringsSep " " [
    "--format av_mkv"
    "--audio-lang-list deu,eng,ita --all-audio"
    "--aencoder copy --audio-copy-mask aac,ac3,eac3,truehd,dts,dtshd,mp3,flac --audio-fallback ac3"
    "--subtitle-lang-list deu,eng,ita --all-subtitles --subtitle-burned=none"
  ];
  cfg = config.nas;
  armDir = "${cfg.servicesDir}/arm";
  media = "${cfg.mediaDir}/Transcode/ARM";
  # Rippen und Umwandeln auf der NVMe, erst das fertige Ergebnis kommt nach tank (completed/).
  # So laufen die HDDs nur beim Verschieben statt stundenlang, und der Rip ist schneller.
  # fast/incomplete hat keine Snapshots (wie bei qBittorrent): in fast/services blieben die
  # geloeschten Roh-Rips in den Snapshots liegen und fuellten den Pool. Ohne fastPool: auf tank.
  work = if cfg.fastPool != null then "/mnt/${cfg.fastPool}/incomplete/arm" else media;
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
          "${media}:/home/arm/media" # completed/
          "${work}:/home/arm/work" # raw/, transcode/
          "${cfg.mediaDir}/Music:/home/arm/music"
          "${startUdev}:/etc/my_init.d/start_udev.sh:ro"
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
      unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir work ];
      preStart = ''
        for d in ${armDir}/home ${armDir}/logs ${armDir}/config ${media} ${work} ${work}/raw ${work}/transcode; do
          install -d -m 2775 -o ${toString config.users.users.lmlzr.uid} -g 989 "$d"
        done
      '';
      # arm.yaml legt der Container beim ersten Start an; danach Vorlagen und OMDb-Key eintragen.
      # ARM liest die Datei bei jedem Rip neu, ein Neustart ist nicht noetig.
      # MANUAL_WAIT_TIME: findet OMDb das Disc-Label nicht, kuerzt ARM es Wort fuer Wort und nimmt
      # den ersten Treffer (MARVELS_THOR_... wurde so "Mechanical Marvels"). 5 min zum Korrigieren.
      # UMASK aus arm.yaml wertet ARM nicht aus, Ordner entstehen mit 755 und Sonarr/Radarr
      # (Gruppe media) koennen nicht importieren. SET_MEDIA_PERMISSIONS chmodet nach dem Rip.
      # ALLOW_DUPLICATES: sonst verweigert ARM jede Disc, die es schon einmal (erfolgreich) gerippt
      # hat ("Duplicate rips are disabled"), auch wenn man sie absichtlich nochmal rippen will.
      postStart = ''
        key=/etc/secrets/arm-omdb-key
        conf=${armDir}/config/arm.yaml
        for _ in $(seq 60); do [ -f "$conf" ] && break; sleep 2; done
        [ -f "$conf" ] || exit 0
        ${pkgs.gnused}/bin/sed -i \
          -e 's|^HB_PRESET_DVD:.*|HB_PRESET_DVD: "H.265 NVENC 1080p"|' \
          -e 's|^HB_PRESET_BD:.*|HB_PRESET_BD: "H.265 NVENC 1080p"|' \
          -e 's|^HB_ARGS_DVD:.*|HB_ARGS_DVD: "${hbArgs}"|' \
          -e 's|^HB_ARGS_BD:.*|HB_ARGS_BD: "${hbArgs}"|' \
          -e 's|^MANUAL_WAIT_TIME:.*|MANUAL_WAIT_TIME: 300|' \
          -e 's|^ALLOW_DUPLICATES:.*|ALLOW_DUPLICATES: true|' \
          -e 's|^SET_MEDIA_PERMISSIONS:.*|SET_MEDIA_PERMISSIONS: true|' \
          -e 's|^CHMOD_VALUE:.*|CHMOD_VALUE: 775|' \
          -e 's|^RAW_PATH:.*|RAW_PATH: "/home/arm/work/raw/"|' \
          -e 's|^TRANSCODE_PATH:.*|TRANSCODE_PATH: "/home/arm/work/transcode/"|' \
          -e 's|^COMPLETED_PATH:.*|COMPLETED_PATH: "/home/arm/media/completed/"|' \
          "$conf"
        # Ohne sdf_Stop haengt makemkvcon (ab 1.17.8) auf Volllast bei "SDF auto", vor dem ersten
        # Lesezugriff. Der Wert steht im MakeMKV-Debug-Log und aendert sich mit dem Laufwerk.
        mk=${armDir}/home/.MakeMKV
        install -d -o ${toString config.users.users.lmlzr.uid} -g 989 "$mk"
        grep -qs '^sdf_Stop' "$mk/settings.conf" \
          || echo 'sdf_Stop = "HL-DT-ST_BD-RE__BH08LS20_1.00_20090330123456_K1G96HE3555"' >> "$mk/settings.conf"
        chown ${toString config.users.users.lmlzr.uid}:989 "$mk/settings.conf"
        [ -s "$key" ] || exit 0
        k=$(tr -d '[:space:]' < "$key")
        ${pkgs.gnused}/bin/sed -i "s|^OMDB_API_KEY:.*|OMDB_API_KEY: \"$k\"|" "$conf"
      '';
    };

    networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ 8095 ];
  };
}
