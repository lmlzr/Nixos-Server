{ config, pkgs, ... }:

# Bitcoin-"Lotterie": Solo-Mining mit cpuminer (sha256d) ueber solo.ckpool.org. Rein zum Spass,
# die Chance auf einen Block liegt bei einem Treffer in Hunderten Millionen Jahren.
# Steuerseite mit Start/Stopp und Wallet-Adresse: http://10.0.0.5:8099 (nur Heimnetz, ohne Login),
# Status als JSON unter /api/status (Homepage-Widget). Die Adresse wird dort eingetragen und
# liegt nur im State-Verzeichnis, nicht im Repo.
# Threads (1-12) auf der Steuerseite einstellbar, ~10 W + 5 W je Thread. Laeuft mit niedrigster
# Prioritaet (idle), andere Dienste haben immer Vorrang.
let
  cfg = config.nas;
  port = 8099;
  maxThreads = 12; # Ryzen 5 3600: 6 Kerne, 12 Threads
in
{
  systemd.services.btc-lottery = {
    description = "Bitcoin-Lotterie (Solo-Mining) mit Steuerseite";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./btc-lottery.py} ${pkgs.cpuminer}/bin/minerd ${toString port} /var/lib/btc-lottery ${toString maxThreads}";
      DynamicUser = true;
      StateDirectory = "btc-lottery";
      Restart = "on-failure";
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
