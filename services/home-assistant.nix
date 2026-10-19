{ config, pkgs, ... }:

{
  services.home-assistant = {
    enable = true;

    extraComponents = [
      "default_config"
      # fuer das Onboarding benoetigt
      "met"
      "radio_browser"
      "isal"

      "esphome"
      "mqtt" # Broker: services/mosquitto.nix (127.0.0.1:1883)
      "bluetooth"
      "zha"
    ];

    config = {
      default_config = { };

      # configuration.yaml wird von NixOS erzeugt; in der UI erstellte
      # Automationen/Szenen/Skripte liegen in eigenen Dateien
      "automation ui" = "!include automations.yaml";
      "scene ui" = "!include scenes.yaml";
      "script ui" = "!include scripts.yaml";

      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = "Europe/Berlin";
      };

      http = {
        server_port = 8123;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "f ${config.services.home-assistant.configDir}/automations.yaml 0644 hass hass"
    "f ${config.services.home-assistant.configDir}/scenes.yaml 0644 hass hass"
    "f ${config.services.home-assistant.configDir}/scripts.yaml 0644 hass hass"
  ];

  hardware.bluetooth.enable = true;

  # Zugriff auf den Zigbee-USB-Stick fuer ZHA
  users.users.hass.extraGroups = [ "dialout" ];

  networking.firewall.allowedTCPPorts = [
    8123
  ];
}
