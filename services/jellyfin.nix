{ config, pkgs, ... }:

let
  # Daten liegen auf ZFS (siehe modules/links.nix, dort auch unter /var/lib/jellyfin)
  source = "${config.nas.servicesDir}/jellyfin";
in
{
  services.jellyfin = {
    enable = true;

    openFirewall = true;

    user = "jellyfin";
    group = "jellyfin";

    # Das Backup stammt aus einem Docker-Jellyfin: Datenbank und Bibliotheksordner
    # erwarten /config/data als Datenverzeichnis. Jellyfin vergleicht die Pfade als
    # Text, deshalb echter Bind-Mount statt Symlink.
    dataDir = "/config/data";
  };

  nas.mounts."/config/data" = {
    device = source;
    fsType = "none";
    options = [ "bind" "nofail" "x-systemd.requires=nas-service-dirs.service" ];
    depends = [ config.nas.servicesDir ];
  };

  # Restliche Docker-Pfade aus Config/Datenbank auf die NixOS-Pfade umleiten
  systemd.tmpfiles.rules = [
    "d  /config               0755 root root -"
    "L+ /config/cache         -    -    -    - /var/cache/jellyfin"
    "d  /data                 0755 root root -"
    "L+ /data/movies          -    -    -    - /mnt/tank/media/Movies"
    "L+ /data/tvshows         -    -    -    - /mnt/tank/media/TV"
    "L+ /data/Books           -    -    -    - /mnt/tank/media/Books"
    "L+ /data/music           -    -    -    - /mnt/tank/media/Music"
  ];

  # Alten Symlink /config/data entfernen, sonst haengt der Bind-Mount ins Symlink-Ziel
  system.activationScripts.jellyfinConfigDataLink.text = ''
    if [ -L /config/data ]; then rm /config/data; fi
  '';
}
