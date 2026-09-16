{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.jellyfin = {
    image = "linuxserver/jellyfin:latest";

    ports = [
      "8069:8096"
      "8920:8920"
    ];

    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "Europe/Berlin";
      NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
    };

    volumes = [
      "/portainer/Files/AppData/Config/Jellyfin:/config"
      "/nfs/jellyfin/Movies:/data/movies"
      "/nfs/jellyfin/Music:/data/music"
      "/nfs/jellyfin/TV:/data/tvshows"
    ];

    autoStart = true;

    extraOptions = [
      "--restart=unless-stopped"
      "--runtime=nvidia"
    ];
  };
}