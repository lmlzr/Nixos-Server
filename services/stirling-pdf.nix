{ config, pkgs, ... }:

{
  services.stirling-pdf = {
    enable = true;

    environment = {
      SERVER_PORT = "8083";
      SYSTEM_DEFAULTLOCALE = "de-DE";
      TZ = "Europe/Berlin";
    };
  };

  networking.firewall.allowedTCPPorts = [
    8083
  ];
}