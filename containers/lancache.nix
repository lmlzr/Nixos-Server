{ config, pkgs, ... }:

{
  virtualisation.oci-containers = {

    backend = "docker";

    containers.lancache-dns = {

      image = "lancachenet/lancache-dns:latest";

      ports = [
        "10.0.0.5:53:53/udp"
        "10.0.0.5:53:53/tcp"
      ];

      environment = {
        USE_GENERIC_CACHE = "true";
        LANCACHE_IP = "10.0.0.5";
        DNS_BIND_IP = "10.0.0.5";
        UPSTREAM_DNS = "1.1.1.1";
        CACHE_ROOT = "/mnt/lancache/lancache";
        CACHE_DISK_SIZE = "2000g";
        MIN_FREE_DISK = "10g";
        CACHE_INDEX_SIZE = "500m";
        CACHE_MAX_AGE = "3650d";
        TZ = "Europe/Berlin";
      };

      autoStart = true;

    };

    containers.lancache-monolithic = {

      image = "lancachenet/monolithic:latest";

      ports = [
        "80:80/tcp"
        "443:443/tcp"
      ];

      environment = {
        USE_GENERIC_CACHE = "true";
        LANCACHE_IP = "10.0.0.5";
        DNS_BIND_IP = "10.0.0.5";
        UPSTREAM_DNS = "1.1.1.1";
        CACHE_ROOT = "/mnt/lancache/lancache";
        CACHE_DISK_SIZE = "2000g";
        MIN_FREE_DISK = "10g";
        CACHE_INDEX_SIZE = "500m";
        CACHE_MAX_AGE = "3650d";
        TZ = "Europe/Berlin";
      };

      volumes = [
        "/mnt/TB1/lancache/cache:/data/cache"
        "/mnt/TB1/lancache/logs:/data/logs"
      ];

      autoStart = true;

    };

  };
}