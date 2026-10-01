{ config, pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    user = "lmlzr";
    group = "users";

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