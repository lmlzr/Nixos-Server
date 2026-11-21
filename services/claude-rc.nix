{ config, pkgs, ... }:

# Claude Code Remote Control beim Booten starten (im Home-Ordner von lmlzr).
# Laeuft in einer eigenen tmux-Sitzung mit eigenem Socket, damit normale tmux-Sitzungen
# beim Stoppen des Dienstes nicht mitbeendet werden.
#   Ansehen:   tmux -L claude-rc attach      (verlassen: Strg+B, dann D)
#   Neustart:  sudo systemctl restart claude-rc
let
  user = "lmlzr";
  home = config.users.users.${user}.home;
  tmux = "${pkgs.tmux}/bin/tmux -L claude-rc";

  start = pkgs.writeShellScript "claude-rc-start" ''
    set -u
    ${tmux} has-session -t claude-rc 2>/dev/null && exit 0
    # network-online gilt schon mit Link-Local-Adresse (DHCP nach Stromausfall verspaetet).
    # Ohne Netz gibt claude sofort auf und niemand startet es neu, also vorher pruefen.
    curl -s -o /dev/null -m 10 https://api.anthropic.com/ || exit 1
    # Login-Shell: gleiche Umgebung (PATH, sudo-Wrapper) wie bei SSH
    ${tmux} new-session -d -s claude-rc -c ${home} "bash -lc 'claude remote-control; exec bash -l'"

    # Im Home-Ordner fragt Claude bei jedem Start "Trust /home/...?" (wird dort nicht
    # gespeichert). Frage abwarten und bestaetigen.
    for i in $(seq 1 90); do
      if ${tmux} capture-pane -p -t claude-rc | grep -q "Trust ${home}"; then
        ${tmux} send-keys -t claude-rc y Enter
        break
      fi
      sleep 1
    done
  '';
in
{
  systemd.services.claude-rc = {
    description = "Claude Code Remote Control (tmux-Sitzung claude-rc)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.bash pkgs.coreutils pkgs.curl pkgs.gnugrep ];
    # Ein Rebuild soll laufende Remote-Sitzungen nicht beenden.
    restartIfChanged = false;
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "15s";
      User = user;
      WorkingDirectory = home;
      ExecStart = start;
      ExecStop = "${tmux} kill-session -t claude-rc";
    };
  };
}
