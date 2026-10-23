{ config, lib, pkgs, ... }:

let
  lancacheIP = "10.0.0.5";
  lan = config.nas.lanInterface;
in
{
  services.nginx.package = pkgs.nginxMainline.override {
    withSlice = true;
  };

  # LAN-Karte nicht von NetworkManager verwalten lassen, sonst kann NM die zusaetzliche
  # statische Lancache-IP beim Reconnect entfernen. DHCP uebernimmt dafuer dhcpcd.
  networking.networkmanager.unmanaged = [ lan ];

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # nginx legt per LogsDirectory nur /var/log/nginx an, das Unterverzeichnis fuer logPrefix fehlt sonst
  systemd.tmpfiles.rules = [ "d ${config.services.lancache.logPrefix} 0750 nginx nginx -" ];

  networking.interfaces.${lan} = {
    useDHCP = true;
    ipv4.addresses = [
      {
        address = lancacheIP;
        prefixLength = 24;
      }
    ];
  };

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
