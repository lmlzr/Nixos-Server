{ config, pkgs, ... }:

{
  services.karakeep = {
    enable = true;

    # Vollständige Installation:
    # - Karakeep
    # - Meilisearch
    # - Chromium für Crawling/Screenshots
    meilisearch.enable = true;
    browser.enable = true;

    fileSystems."/var/lib/karakeep" = {
      device = "/mnt/tb1/server/services/karakeep";
      options = [ "bind" ];
    };

    extraEnvironment = {
      # Adresse deiner Karakeep-Instanz
      NEXTAUTH_URL = "http://127.0.0.1:3000";

      # Neue Registrierungen erlauben
      DISABLE_SIGNUPS = "false";

      # Weniger Logs
      LOG_LEVEL = "notice";

      # Keine automatische Release-Abfrage
      DISABLE_NEW_RELEASE_CHECK = "true";
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [
    3000
  ];
}