{ config, pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    user = "lmlzr";
    group = "users";

    dataDir = "/home/lmlzr";

    configDir = "/home/lmlzr/.config/syncthing";

    guiAddress = "0.0.0.0:8384";

  };

  networking.firewall.allowedTCPPorts = [
    8384
    22000
  ];

  networking.firewall.allowedUDPPorts = [
    22000
  ];

}