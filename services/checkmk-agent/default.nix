{ config, lib, pkgs, ... }:

# Checkmk-Agent im klassischen Pull-Modus: der Checkmk-Server fragt TCP 6556 ab
# (unverschluesselt, wie das offizielle check-mk-agent.socket.fallback).
# Zugriff nur aus allowedFrom und nur ueber die LAN-Schnittstelle.
let
  cfg = config.services.checkmk-agent;
  agent = pkgs.callPackage ./package.nix { };

  # MK_LIBDIR: plugins/ (Unterordner = Cache-Intervall in Sekunden) und local/
  libDir = pkgs.runCommand "checkmk-agent-lib" { } (''
    mkdir -p $out/plugins $out/local
  '' + lib.optionalString cfg.smart.enable ''
    mkdir -p $out/plugins/${toString cfg.smart.interval}
    ln -s ${agent}/share/check_mk_agent/plugins/smart $out/plugins/${toString cfg.smart.interval}/smart
  '');

  environment = {
    MK_LIBDIR = "${libDir}";
    MK_CONFDIR = "/etc/check_mk";
    MK_VARDIR = "/var/lib/check_mk_agent";
    MK_LOGDIR = "/var/log/check_mk_agent";
    MK_BIN = "${agent}/bin";
  };

  # Programme, die der Agent und das SMART-Plugin aufrufen
  path = with pkgs; [
    coreutils gnugrep gnused gawk findutils procps util-linux iproute2 ethtool
    config.systemd.package smartmontools
  ] ++ lib.optional config.boot.zfs.enabled config.boot.zfs.package
    ++ lib.optional config.virtualisation.docker.enable config.virtualisation.docker.package;
in
{
  options.services.checkmk-agent = {
    enable = lib.mkEnableOption "Checkmk-Agent (Pull-Modus auf TCP 6556)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6556;
    };

    allowedFrom = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1" "::1" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" ];
      example = [ "10.0.0.20" ];
      description = "Adressen/Netze, die den Agent abfragen duerfen. Am besten nur die IP des Checkmk-Servers.";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = config.nas.lanInterface or "enp3s0";
      description = "Nur auf dieser Schnittstelle wird der Port in der Firewall geoeffnet.";
    };

    smart = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "SMART-Werte der Platten an Checkmk liefern.";
      };
      interval = lib.mkOption {
        type = lib.types.ints.positive;
        default = 86400;
        description = ''
          Das SMART-Plugin weckt schlafende HDDs (ruft smartctl ohne -n standby auf).
          Deshalb laeuft es zwischengespeichert nur alle `interval` Sekunden (Standard: 1x taeglich).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ agent ];

    systemd.sockets.check-mk-agent = {
      description = "Checkmk Agent Socket";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = cfg.port;
        Accept = true;
        MaxConnectionsPerSource = 3;
        # Zusaetzlich zur Firewall: nur diese Absender
        IPAddressDeny = "any";
        IPAddressAllow = cfg.allowedFrom;
      };
    };

    systemd.services."check-mk-agent@" = {
      description = "Checkmk Agent";
      inherit path;
      environment = environment // {
        MK_RUN_ASYNC_PARTS = "false";
        MK_READ_REMOTE = "true";
      };
      serviceConfig = {
        # "-": Exitcode wird protokolliert, die Unit aber nicht als fehlgeschlagen markiert
        ExecStart = "-${agent}/bin/check_mk_agent";
        StandardInput = "socket";
        User = "root";
      };
    };

    # Zwischengespeicherte Teile (z. B. SMART-Plugin) im Hintergrund
    systemd.services.check-mk-agent-async = {
      description = "Checkmk Agent - asynchrone Hintergrundaufgaben";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      inherit path;
      environment = environment // {
        MK_RUN_SYNC_PARTS = "false";
        MK_LOOP_INTERVAL = "60";
      };
      serviceConfig = {
        ExecStart = "${agent}/bin/check_mk_agent";
        User = "root";
        Restart = "on-failure";
      };
    };

    systemd.tmpfiles.rules = [
      "d /etc/check_mk 0755 root root -"
      "d /var/lib/check_mk_agent 0755 root root -"
      "d /var/log/check_mk_agent 0755 root root -"
    ];

    networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [ cfg.port ];
  };
}
