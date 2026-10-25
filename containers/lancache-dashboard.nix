{ config, pkgs, ... }:

let
  port = 3000;
  # Datenbank + Steam-Depot-Mapping (~100 MB) auf dem Pool
  dataDir = "${config.nas.servicesDir}/lancache-dashboard";
  logDir = config.services.lancache.logPrefix;
in
{
  # Web-Dashboard fuer den Lancache: Downloads, HIT/MISS, Clients, gecachte Spiele
  # https://github.com/imahmud1/lancache-dashboard  ->  http://neotokyo:3000
  virtualisation.oci-containers = {

    backend = "docker";

    containers.lancache-dashboard = {

      image = "ghcr.io/imahmud1/lancache-dashboard:latest";

      ports = [ "${toString port}:3000" ];

      volumes = [
        "${logDir}:/logs:ro"
        "${dataDir}:/app/data"
      ];

      environment = {
        LOG_PATH = "/logs/access.log";
        DB_PATH = "/app/data/lancache.db";
        # SteamPrefill laeuft auf dem Server selbst und kommt ueber die Lancache-IP
        PREFILL_IPS = "10.0.0.5";
        RESOLVE_HOSTNAMES = "true"; # Namen ueber Pi-hole
        CACHE_MAX_AGE_DAYS = "300"; # wie services.lancache.cacheMaxAge
        BRAND_NAME = "neotokyo";
      };

      # Container laeuft als UID 1001; Gruppe nginx (60) darf das Log lesen (Ordner 0750 nginx:nginx)
      extraOptions = [ "--group-add=60" ];

      autoStart = true;

    };

  };

  systemd.services.docker-lancache-dashboard = {
    unitConfig.RequiresMountsFor = [ dataDir ];
    preStart = ''
      mkdir -p ${dataDir}
      chown 1001:1001 ${dataDir}
    '';
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
