{ config, pkgs, ... }:

{
  imports = [
    ./sonarr.nix
    ./radarr.nix
    ./lidarr.nix
    ./prowlarr.nix
    ./qbittorrent.nix
  ];

  # Gemeinsame Gruppe, damit Downloads, *arr und Jellyfin auf dieselben Dateien zugreifen.
  # Downloads liegen in ${config.nas.mediaDir}/downloads (gleiches Dataset -> Hardlinks).
  # Den Ordner legt Hardware/storage.nix an.
  users.groups.media = { };
  users.users.jellyfin.extraGroups = [ "media" ];
}
