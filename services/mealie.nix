{ config, pkgs, ... }:

{
  services.mealie = {
    enable = true;

    listenAddress = "0.0.0.0";
    port = 9925;

    settings = {
      TZ = "Europe/Berlin";
      BASE_URL = "http://10.0.0.5:9925";

      ALLOW_SIGNUP = "false";

      DB_ENGINE = "sqlite";
    };
  };

  networking.firewall.allowedTCPPorts = [
    9925
  ];
}