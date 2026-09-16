{ config, pkgs, ... }:

{
  virtualisation.oci-containers = {

    backend = "docker";

    containers.Firefox = {

      image = "linuxserver/firefox:latest";

      ports = [
        "4044:3000"
        "4045:3001"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        NVIDIA_DRIVER_CAPABILITIES = "all";
        DISPLAY = ":1";
        START_DOCKER = "true";
        PIXELFLUX_WAYLAND = "true";
        SELKIES_ENCODER = "x264enc,jpeg";
        DISABLE_ZINK = "false";
        DISABLE_DRI3 = "false";
        TITLE = "Firefox";
      };

      volumes = [
        "/portainer/Files/AppData/Config/firefox:/config"
      ];

      autoStart = true;

      extraOptions = [
        "--restart=unless-stopped"
        "--runtime=nvidia"
      ];

    };

  };

  systemd.tmpfiles.rules = [
    "d /portainer/Files/AppData/Config/firefox 0755 root root -"
  ];

}