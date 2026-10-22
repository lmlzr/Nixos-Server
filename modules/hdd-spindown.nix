{ config, lib, pkgs, ... }:

# Spindown der Daten-HDDs per hd-idle. Systemplatte und SSD werden nie abgeschaltet.
# Hinweis: Die Platten schlafen nur ein, wenn 15 min wirklich nichts auf den Pool
# schreibt oder liest. Dienst-Daten (tank/services), stuendliche Snapshots oder
# laufende Downloads halten sie wach.
let
  cfg = config.nas.spindown;

  diskArgs = lib.concatMap (disk: [ "-a" disk "-i" (toString (cfg.idleMinutes * 60)) ]) cfg.disks;
in
{
  options.nas.spindown = {
    enable = lib.mkEnableOption "Spindown der Daten-HDDs bei Leerlauf (hd-idle)";

    idleMinutes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "Minuten ohne Zugriff, bevor eine Platte abgeschaltet wird.";
    };

    disks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/dev/disk/by-id/wwn-0x5000c500e7ab0441"
        "/dev/disk/by-id/wwn-0x5000c500e7aafd88"
      ];
      description = "Platten, die abgeschaltet werden duerfen (stabile Pfade aus /dev/disk/by-id).";
    };

    commandType = lib.mkOption {
      type = lib.types.enum [ "ata" "scsi" ];
      default = "ata";
      description = "Befehl zum Abschalten: ata fuer SATA-Platten, scsi fuer USB-Gehaeuse.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.hd-idle ];

    systemd.services.hd-idle = {
      description = "Spindown der Daten-HDDs nach ${toString cfg.idleMinutes} min Leerlauf";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        # -i 0 vorneweg: alle nicht genannten Platten nie abschalten.
        # -s 1: wwn-Symlinks auch spaeter aufloesen (Platte erst nach dem Start da).
        ExecStart = lib.escapeShellArgs ([
          (lib.getExe pkgs.hd-idle)
          "-i" "0"
          "-c" cfg.commandType
          "-s" "1"
        ] ++ diskArgs);
        Restart = "always";
        RestartSec = "10s";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
