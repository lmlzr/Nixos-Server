{ config, pkgs, ... }:

{
  virtualisation.oci-containers = {
    backend = "docker";

    containers.portainer = {
      image = "portainer/portainer-ce:latest";

      ports = [
        "9443:9443"
      ];

      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "portainer_data:/data"
      ];

      extraOptions = [
        "--restart=unless-stopped"
      ];
    };
  };
}