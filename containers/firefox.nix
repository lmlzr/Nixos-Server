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

      volumes = [
        "/portainer/Files/AppData/Config/firefox:/config"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TITLE = "Firefox";
        NVIDIA_DRIVER_CAPABILITIES = "all";
      };

      autoStart = true;

    };

  };
}