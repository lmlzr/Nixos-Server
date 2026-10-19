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
      };

      # Login fuer die Web-Oberflaeche. Datei anlegen (0600) mit:
      #   CUSTOM_USER=lmlzr
      #   PASSWORD=...
      environmentFiles = [ "/etc/secrets/firefox.env" ];

      autoStart = true;

    };

  };
}
