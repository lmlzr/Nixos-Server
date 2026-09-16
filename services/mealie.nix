{ config, pkgs, ... }:

{
  services.mealie = {
    enable = true;

    listenAddress = "0.0.0.0";
    port = 9925;

    settings = {
      TZ = "Europe/Berlin";
      BASE_URL = "http://127.0.0.1:9925";

      ALLOW_SIGNUP = "true";

      DB_ENGINE = "sqlite";
      DATA_DIR = "/mnt/tb1/server/services/mealie";
    };
  };

  networking.firewall.allowedTCPPorts = [
    9925
  ];
}