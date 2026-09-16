{ config, pkgs, ... }:

{
  services.mealie = {
    enable = true;

    listenAddress = "0.0.0.0";
    port = 9925;

    settings = {
      TZ = "Europe/Berlin";
      BASE_URL = "http://192.168.1.100:9925";

      ALLOW_SIGNUP = "true";

      DB_ENGINE = "sqlite";
      DATA_DIR = "/var/lib/mealie";
    };
  };

  networking.firewall.allowedTCPPorts = [
    9925
  ];
}