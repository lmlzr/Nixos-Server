{ config, pkgs, ... }:

let
  # SteamPrefill speichert Login + Spieleauswahl in ./Config relativ zum Arbeitsverzeichnis
  workDir = "/var/lib/steam-prefill";
in
{
  environment.systemPackages = [ pkgs.steam-lancache-prefill ];

  systemd.tmpfiles.rules = [
    "d ${workDir} 0750 lmlzr users -"
  ];

  # Einmalig einrichten: cd /var/lib/steam-prefill && SteamPrefill select-apps
  systemd.services.steam-prefill = {
    description = "SteamPrefill: Lancache vorwaermen";
    after = [ "network-online.target" "nginx.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "lmlzr";
      WorkingDirectory = workDir;
      ExecStart = "${pkgs.steam-lancache-prefill}/bin/SteamPrefill prefill --no-ansi";
    };
  };

  systemd.timers.steam-prefill = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
