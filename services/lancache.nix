{ config, lib, pkgs, ... }:

let
  lancacheIP = "10.0.0.5";
in
{
  services.nginx.package = pkgs.nginxMainline.override {
    withSlice = true;
  };

  # enp3s0 nicht von NetworkManager verwalten lassen, sonst kann NM die zusaetzliche
  # statische Lancache-IP beim Reconnect entfernen. DHCP uebernimmt dafuer dhcpcd.
  networking.networkmanager.unmanaged = [ "enp3s0" ];
  networking.interfaces.enp3s0.useDHCP = true;

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  networking.interfaces.enp3s0.ipv4.addresses = [
    {
      address = lancacheIP;
      prefixLength = 24;
    }
  ];

  services.lancache = {
    enable = true;

    cacheLocation = config.nas.lancacheDir; # Dataset mit 2-TB-Quota
    logPrefix = "/var/log/nginx/lancache";

    listenAddress = lancacheIP;

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