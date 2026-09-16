{ config, pkgs, ... }:

{
  virtualisation.oci-containers = {
    backend = "docker";

    containers.portainer = {
      image = "portainer/portainer-ce:2.21.4";

      ports = [
        "127.0.0.1:9443:9443"
      ];

      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "/var/lib/portainer:/data"
      ];

      autoStart = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/portainer 0700 root root -"
  ];
}