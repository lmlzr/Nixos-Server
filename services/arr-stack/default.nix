{ config, pkgs, ... }:

{
  imports = [
    ./sonarr.nix
    ./radarr.nix
    ./lidarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix
  ];

  # Gemeinsame Gruppe, damit Downloads, *arr und Jellyfin auf dieselben Dateien zugreifen
  users.groups.media = { };
  users.users.jellyfin.extraGroups = [ "media" ];

  systemd.tmpfiles.rules = [
    "d /mnt/TB1/media 2775 root media -"
  ];
}
