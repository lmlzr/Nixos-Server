{ config, lib, pkgs, ... }:

# Ueberwachung von Platten und Pool. Benachrichtigungen gehen ins Journal, per wall an
# angemeldete Benutzer und per Mail an nas.mail.alertTo (modules/mail.nix).
let
  pool = config.nas.pool;
  mail = config.nas.mail;
in
{
  # SMART: alle Platten automatisch, Kurztest taeglich 02:00, Langtest am 1. des Monats 03:00
  # (Langtest dauert bei 16 TB viele Stunden). Temperaturwarnung ab 45 °C, kritisch ab 55 °C.
  services.smartd = {
    enable = true;
    autodetect = true;
    defaults.autodetected = "-a -o on -S on -n standby,q -s (S/../.././02|L/../01/./03) -W 4,45,55";
    notifications.wall.enable = true;
    notifications.mail = {
      enable = true;
      sender = mail.from;
      recipient = mail.alertTo;
    };
  };

  # ZFS Event Daemon: meldet Plattenfehler, Resilver und Scrub-Ergebnisse
  services.zfs.zed.settings = {
    ZED_NOTIFY_VERBOSE = true; # auch erfolgreiche Scrubs melden
    ZED_SCRUB_AFTER_RESILVER = true;
    ZED_USE_ENCLOSURE_LEDS = true;
    ZED_EMAIL_ADDR = [ mail.alertTo ];
    ZED_EMAIL_PROG = "${pkgs.msmtp}/bin/msmtp";
    ZED_EMAIL_OPTS = "@ADDRESS@";
    ZED_NOTIFY_INTERVAL_SECS = 3600; # gleiche Meldung hoechstens stuendlich
  };

  # Taeglicher Gesundheitscheck: schreibt bei Problemen einen Fehler ins Journal
  # (journalctl -p err -u zfs-health), an alle Terminals und per Mail
  systemd.services.zfs-health = {
    description = "ZFS: Pool-Zustand und Belegung pruefen";
    onFailure = [ "notify-mail@%n.service" ];
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
