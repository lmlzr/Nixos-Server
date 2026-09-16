{ config, pkgs, ... }:

{
  services.home-assistant = {
    enable = true;

    configDir = "/mnt/tb1/server/services/homeassistant";

    extraComponents = [
      "default_config"
      "esphome"
      "mqtt"
      "bluetooth"
      "zha"
    ];

    config = {
      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = "Europe/Berlin";
      };

      http = {
        server_port = 8123;
      };

      # Beispiel:
      # mqtt = {
      #   broker = "127.0.0.1";
      #   port = 1883;
      # };
    };
  };

  networking.firewall.allowedTCPPorts = [
    8123
  ];
}