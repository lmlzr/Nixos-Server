{ config, pkgs, ... }:

{
  services.karakeep = {
    enable = true;

    meilisearch.enable = true;
    browser.enable = true;

    extraEnvironment = {
      NEXTAUTH_URL = "http://127.0.0.1:3000";

      DISABLE_SIGNUPS = "false";

      # Keine automatische Release-Abfrage
      DISABLE_NEW_RELEASE_CHECK = "true";
    };
  };

  networking.firewall.allowedTCPPorts = [
    3000
  ];
}