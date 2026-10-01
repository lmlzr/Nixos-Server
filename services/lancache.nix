{ config, lib, pkgs, ... }:

let
  lancacheIP = "10.0.0.5";
in
{
  services.nginx.package = pkgs.nginxMainline.override {
    withSlice = true;
  };
  services.nginx.defaultListenAddresses = [
    "10.0.0.1"
  ];

  networking.interfaces.enp3s0.ipv4.addresses = [
    {
      address = lancacheIP;
      prefixLength = 24;
    }
  ];

  services.lancache = {
    enable = true;

    # ZFS/TB1
    cacheLocation = "/mnt/TB1/lancache";

    # Logs
    logPrefix = "/var/log/nginx/lancache";

    # LanCache lauscht auf dieser IP auf 80 + 443
    listenAddress = lancacheIP;

    # DNS, den LanCache für die Upstream-Auflösung verwendet
    upstreamDns = [
      "10.0.0.1"
      "1.1.1.1"
    ];

    cacheDiskSize = "2000g";
    cacheIndexSize = "500m";
    cacheMaxAge = "300d";
    minFreeDisk = "100g";
    sliceSize = "1m";
    logFormat = "cachelog";
    workerProcesses = "auto";
  };

}