{ config, pkgs, ... }:

{
  services.karakeep = {
    enable = true;

    meilisearch.enable = true;
    browser.enable = true;

    extraEnvironment = {
      NEXTAUTH_URL = "http://10.0.0.5:3000";

      # Fuer den ersten Account kurz auf "false" setzen
      DISABLE_SIGNUPS = "true";

      # Keine automatische Release-Abfrage
      DISABLE_NEW_RELEASE_CHECK = "true";
    };
  };

  networking.firewall.allowedTCPPorts = [
    3000
  ];
}