{ config, lib, pkgs, ... }:

# Automatische Snapshots mit sanoid. Snapshots schuetzen vor versehentlichem Loeschen
# und Verschluesselungstrojanern (SMB-Benutzer koennen sie nicht loeschen).
# Sie ersetzen KEIN Backup auf einem anderen Datentraeger.
#
# Spindown: sanoid fasst bei jedem Lauf ALLE Pools an (zfs allow auf jedes Dataset, Snapshot-Liste
# aller Pools). Mit SSD-Pool laeuft sanoid deshalb nur taeglich 03:25 (kurz vor syncoid 03:30,
# HDDs sind dann ohnehin wach); die stuendlichen Snapshots der SSD macht ein eigener Timer,
# der nur den Pool fast anfasst.
let
  cfg = config.nas;
  pool = cfg.pool;
  onSsd = cfg.fastPool != null;
  zfs = "${config.boot.zfs.package}/bin/zfs";
  keepHourly = 24;
in
{
  services.sanoid = {
    enable = true;
    interval = if onSsd then "*-*-* 03:25:00" else "hourly";

    templates = {
      # Medien sind gross und wiederbeschaffbar: kurze Aufbewahrung, sonst bleibt
      # Platz von geloeschten/ersetzten Filmen lange belegt
      media = { hourly = 0; daily = 7; monthly = 0; yearly = 0; autosnap = true; autoprune = true; };
      # Nur taeglich: stuendliche Snapshots wuerden die HDDs jede Stunde aus dem Spindown wecken
      share = { hourly = 0; daily = 30; monthly = 6; yearly = 0; autosnap = true; autoprune = true; };
      # Auf der SSD stuendlich (vom Timer unten, sanoid raeumt mit auf), auf HDD nur taeglich
      services = { hourly = if onSsd then keepHourly else 0; daily = 14; monthly = 3; yearly = 0; autosnap = true; autoprune = true; };
      # Kopie von syncoid: keine eigenen Snapshots, nur alte aufraeumen
      backup = { hourly = 0; daily = 30; monthly = 6; yearly = 0; autosnap = false; autoprune = true; };
    };

    # tank selbst und tank/lancache bekommen bewusst keine Snapshots
    datasets = {
      "${pool}/media".use_template = [ "media" ];
      "${pool}/share".use_template = [ "share" ];
      ${cfg.servicesDataset}.use_template = [ "services" ];
    } // lib.optionalAttrs onSsd {
      ${cfg.servicesBackupDataset}.use_template = [ "backup" ];
    };
  };

  # Stuendliche Snapshots nur fuer die Dienst-Daten auf der SSD, Namensschema wie sanoid
  systemd.services.fast-hourly-snapshot = lib.mkIf onSsd {
    description = "Stuendlicher Snapshot von ${cfg.servicesDataset} (nur SSD-Pool)";
    unitConfig.RequiresMountsFor = [ cfg.servicesDir ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.coreutils pkgs.gnugrep pkgs.findutils ];
    script = ''
      ${zfs} snapshot "${cfg.servicesDataset}@autosnap_$(date +%Y-%m-%d_%H:%M:%S)_hourly"
      ${zfs} list -H -t snapshot -o name -s creation -d 1 "${cfg.servicesDataset}" \
        | grep '_hourly$' | head -n -${toString keepHourly} | xargs -r -n1 ${zfs} destroy
    '';
  };
  systemd.timers.fast-hourly-snapshot = lib.mkIf onSsd {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "hourly"; Persistent = true; };
  };
}
