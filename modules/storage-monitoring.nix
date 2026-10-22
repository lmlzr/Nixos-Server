{ config, lib, pkgs, ... }:

# Ueberwachung von Platten und Pool. Benachrichtigungen gehen vorerst nur ins
# Journal und per wall an angemeldete Benutzer; Mail/ntfy folgt mit dem Backup-Konzept.
let
  pool = config.nas.pool;
in
{
  # SMART: alle Platten automatisch, Kurztest taeglich 02:00, Langtest am 1. des Monats 03:00
  # (Langtest dauert bei 16 TB viele Stunden). Temperaturwarnung ab 45 °C, kritisch ab 55 °C.
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.autodetected = "-a -o on -S on -n standby,q -s (S/../.././02|L/../01/./03) -W 4,45,55";
    notifications.wall.enable = true;
  };

  # ZFS Event Daemon: meldet Plattenfehler, Resilver und Scrub-Ergebnisse
  services.zfs.zed.settings = {
    ZED_NOTIFY_VERBOSE = true; # auch erfolgreiche Scrubs melden
    ZED_SCRUB_AFTER_RESILVER = true;
    ZED_USE_ENCLOSURE_LEDS = true;
  };

  # Taeglicher Gesundheitscheck: schreibt bei Problemen einen Fehler ins Journal
  # (journalctl -p err -u zfs-health) und an alle Terminals
  systemd.services.zfs-health = {
    description = "ZFS: Pool-Zustand und Belegung pruefen";
    serviceConfig.Type = "oneshot";
    path = [ config.boot.zfs.package pkgs.util-linux pkgs.gawk ];
    script = ''
      status=$(zpool status -x ${pool})
      cap=$(zpool list -H -o capacity ${pool} | tr -d %)
      problem=""
      case "$status" in
        *"is healthy"*) ;;
        *) problem="Pool ${pool} ist nicht gesund: $status" ;;
      esac
      if [ "$cap" -ge 80 ]; then
        problem="$problem Pool ${pool} ist zu $cap % voll."
      fi
      if [ -n "$problem" ]; then
        echo "$problem" >&2
        wall "neotokyo: $problem"
        exit 1
      fi
      echo "Pool ${pool} gesund, $cap % belegt."
    '';
  };
  systemd.timers.zfs-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
