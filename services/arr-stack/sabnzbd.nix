{ config, lib, pkgs, ... }:

# SABnzbd: Usenet-Downloader fuer den arr-Stack, http://10.0.0.5:8085
#
# Usenet braucht zwei Dinge (beides kostenpflichtig bzw. mit Konto):
#   1. Einen Usenet-Provider (Zugang zu den Servern): in SABnzbd unter Config -> Servers eintragen
#      (Host, Port 563, SSL an, Benutzer, Passwort, Verbindungen laut Tarif).
#   2. Einen oder mehrere Indexer (Suche): in Prowlarr unter Indexers hinzufuegen, Prowlarr gibt
#      sie an Sonarr/Radarr/Lidarr/Bookshelf weiter.
# Kein VPN noetig: Die Verbindung zum Provider ist per SSL verschluesselt, es wird nichts hochgeladen.
#
# Einstellungen aus der Weboberflaeche bleiben erhalten (allowConfigWrite). Was hier in settings
# steht, wird bei jedem Start erzwungen.
#
# API-Key/NZB-Key: /etc/secrets/sabnzbd-keys.ini, wird beim ersten Start erzeugt (Gruppe media,
# damit die Einrichtungsskripte der arr-Apps ihn lesen koennen).
let
  cfg = config.nas;
  port = 8085;
  keys = "/etc/secrets/sabnzbd-keys.ini";
  incomplete = "${cfg.servicesDir}/sabnzbd/incomplete";
  complete = "${cfg.mediaDir}/downloads/usenet";

  genKeys = pkgs.writeShellScript "sabnzbd-keys" ''
    set -eu
    if [ ! -e ${keys} ]; then
      umask 027
      rand() { ${pkgs.openssl}/bin/openssl rand -hex 16; }
      printf '[misc]\napi_key = %s\nnzb_key = %s\n' "$(rand)" "$(rand)" > ${keys}
      chgrp media ${keys}
    fi
  '';

  # Kategorie -> Unterordner in downloads/usenet (die arr-Apps schicken ihre Kategorie mit)
  category = name: {
    inherit name;
    dir = name;
    pp = "";
    script = "Default";
    priority = -100; # Standard
  };
in
{
  services.sabnzbd = {
    enable = true;
    group = "media";
    allowConfigWrite = true; # Provider-Zugang u. a. in der Weboberflaeche pflegen
    secretFiles = [ keys ];
    settings = {
      misc = {
        host = "0.0.0.0";
        inherit port;
        host_whitelist = "neotokyo, 10.0.0.5";
        # Unfertiges auf der NVMe (HDDs schlafen weiter), fertig nach tank/media/downloads/usenet
        download_dir = incomplete;
        complete_dir = complete;
        permissions = "775";
      };
      categories = {
        "*" = category "*" // { dir = ""; pp = "3"; priority = 0; };
        tv = category "tv";
        movies = category "movies";
        music = category "music";
        books = category "books";
      };
    };
  };

  systemd.services.sabnzbd-keys = {
    description = "SABnzbd: API-Key beim ersten Start erzeugen";
    wantedBy = [ "multi-user.target" ];
    before = [ "sabnzbd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = genKeys;
    };
  };

  systemd.services.sabnzbd = {
    requires = [ "sabnzbd-keys.service" ];
    after = [ "sabnzbd-keys.service" ];
    unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir ];
  };

  systemd.tmpfiles.rules = [
    "d ${cfg.servicesDir}/sabnzbd 0755 sabnzbd media -"
    "d ${incomplete} 2775 sabnzbd media -"
    "d ${complete} 2775 sabnzbd media -"
  ];

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
