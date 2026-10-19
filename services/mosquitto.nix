{ config, pkgs, ... }:

{
  # MQTT-Broker fuer Home Assistant, nur lokal erreichbar.
  # Fuer Geraete im LAN: address weglassen, users mit passwordFile anlegen
  # und Port 1883 in der Firewall oeffnen.
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
        acl = [ "topic readwrite #" ];
      }
    ];
  };
}
