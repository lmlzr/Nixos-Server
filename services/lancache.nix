{ config, lib, pkgs, ... }:

let
  lancacheIP = "10.0.0.5";
  lan = config.nas.lanInterface;
in
{
  services.nginx.package = pkgs.nginxMainline.override {
    withSlice = true;
  };
  # lancache.nix haengt "worker_processes" per appendConfig an, nixpkgs (ab 2026-11) schreibt es
  # selbst (services.nginx.workerProcesses, default auto) -> "directive is duplicate", nginx startet nicht
  services.nginx.appendConfig = lib.mkForce "";

  # LAN-Karte nicht von NetworkManager verwalten lassen, sonst kann NM die zusaetzliche
  # statische Lancache-IP beim Reconnect entfernen. DHCP uebernimmt dafuer dhcpcd.
  networking.networkmanager.unmanaged = [ lan ];

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # nginx legt per LogsDirectory nur /var/log/nginx an, das Unterverzeichnis fuer logPrefix fehlt sonst
  systemd.tmpfiles.rules = [ "d ${config.services.lancache.logPrefix} 0750 nginx nginx -" ];

  # Die nginx-Regel von NixOS erfasst nur /var/log/nginx/*.log, nicht den Unterordner. Rotiert
  # wird hier und nicht im LANCache Manager (der sucht nginx nur in Docker-Containern).
  services.logrotate.settings.lancache = {
    files = "${config.services.lancache.logPrefix}/*.log";
    frequency = "weekly";
    rotate = 8;
    compress = true;
    delaycompress = true;
    sharedscripts = true;
    su = "nginx nginx";
    postrotate = "[ ! -f /var/run/nginx/nginx.pid ] || kill -USR1 `cat /var/run/nginx/nginx.pid`";
  };

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
