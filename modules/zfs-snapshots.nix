{ config, lib, ... }:

# Automatische Snapshots mit sanoid. Snapshots schuetzen vor versehentlichem Loeschen
# und Verschluesselungstrojanern (SMB-Benutzer koennen sie nicht loeschen).
# Sie ersetzen KEIN Backup auf einem anderen Datentraeger.
let
  pool = config.nas.pool;
  onSsd = config.nas.fastPool != null;
in
{
  services.sanoid = {
    enable = true;
    interval = "hourly";

    templates = {
      # Medien sind gross und wiederbeschaffbar: kurze Aufbewahrung, sonst bleibt
      # Platz von geloeschten/ersetzten Filmen lange belegt
      media = { hourly = 0; daily = 7; monthly = 0; yearly = 0; autosnap = true; autoprune = true; };
      # Nur taeglich: stuendliche Snapshots wuerden die HDDs jede Stunde aus dem Spindown wecken
      share = { hourly = 0; daily = 30; monthly = 6; yearly = 0; autosnap = true; autoprune = true; };
      # Auf der SSD stuendlich (kein Spindown), auf HDD nur taeglich
      services = { hourly = if onSsd then 24 else 0; daily = 14; monthly = 3; yearly = 0; autosnap = true; autoprune = true; };
      # Kopie von syncoid: keine eigenen Snapshots, nur alte aufraeumen
      backup = { hourly = 0; daily = 30; monthly = 6; yearly = 0; autosnap = false; autoprune = true; };
    };

    # tank selbst und tank/lancache bekommen bewusst keine Snapshots
    datasets = {
      "${pool}/media".use_template = [ "media" ];
      "${pool}/share".use_template = [ "share" ];
      ${config.nas.servicesDataset}.use_template = [ "services" ];
    } // lib.optionalAttrs onSsd {
      ${config.nas.servicesBackupDataset}.use_template = [ "backup" ];
    };
  };
}
