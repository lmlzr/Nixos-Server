{ config, lib, pkgs, ... }:

# Cleanuparr: raeumt haengende Downloads auf. Torrents, die keine Metadaten bekommen,
# "stalled" bleiben oder zu langsam sind, sammeln Strikes; ab einer Grenze werden sie aus
# qBittorrent entfernt, in Sonarr/Radarr geblocklistet und dort neu gesucht.
# Nativ aus nixpkgs (kein NixOS-Modul vorhanden, daher eigene Unit), Daten (SQLite) in
# /var/lib/private/cleanuparr -> Bind-Mount nach servicesDir (modules/links.nix).
# Heimnetz: http://10.0.0.5:11011 , Einrichtung in der Web-UI:
#   Download Clients: qBittorrent http://192.168.15.1:8080 (Login wie in Sonarr)
#   Arrs: Sonarr http://localhost:8989, Radarr http://localhost:7878 (API-Keys)
#   Queue Cleaner: an, Regeln fuer Stalled + Downloading Metadata
let
  port = 11011;
in
{
  systemd.services.cleanuparr = {
    description = "Cleanuparr: haengende Downloads aufraeumen und neu suchen";
    after = [ "network-online.target" "sonarr.service" "radarr.service" "qbittorrent.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      PORT = toString port;
      BIND_ADDRESS = "0.0.0.0";
      CLEANUPARR_CONFIG_PATH = "/var/lib/cleanuparr";
      DOTNET_CLI_TELEMETRY_OPTOUT = "1";
      HOME = "/var/lib/cleanuparr";
    };
    serviceConfig = {
      ExecStart = lib.getExe pkgs.cleanuparr;
      DynamicUser = true;
      StateDirectory = "cleanuparr";
      Restart = "on-failure";
      RestartSec = 10;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  networking.firewall.interfaces.${config.nas.lanInterface}.allowedTCPPorts = [ port ];
}
