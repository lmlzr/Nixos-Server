{ config, lib, pkgs, ... }:

# Immich: Foto- und Video-Sicherung vom Handy (wie Google Fotos), http://10.0.0.5:2283
# Erster Aufruf legt das Admin-Konto an. Handy-App "Immich", Server-URL wie oben.
#
# Ablage:
#   /mnt/tank/immich         Originale (Dataset tank/immich, sanoid-Snapshots)
#   .../immich/thumbs        Vorschaubilder, per Bind-Mount auf der NVMe: Durchblaettern der
#                            Galerie weckt die HDDs nicht und ist schneller
#   Datenbank (PostgreSQL)   /var/lib/postgresql (Systemplatte)
#   Gesichter/Suche (ML)     laeuft auf der CPU, Modelle werden nach 5 min Leerlauf entladen
#
# Einmalig vor dem ersten Rebuild:
#   sudo zfs create -o mountpoint=legacy -o recordsize=1M tank/immich
#   sudo mkdir -p /mnt/fast/services/immich-thumbs
let
  cfg = config.nas;
  dataset = "${cfg.pool}/immich";
  media = "${cfg.root}/immich";
  thumbs = "${cfg.servicesDir}/immich-thumbs";
in
{
  nas.mounts.${media} = {
    device = dataset;
    fsType = "zfs";
    options = [ "nofail" ];
  };
  # Vorschaubilder auf der NVMe
  nas.mounts."${media}/thumbs" = {
    device = thumbs;
    fsType = "none";
    options = [ "bind" "nofail" "x-systemd.requires-mounts-for=${media}" "x-systemd.requires-mounts-for=${cfg.servicesDir}" ];
  };

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    mediaLocation = media;
    machine-learning.environment = {
      MACHINE_LEARNING_MODEL_TTL = "300"; # ML-Modelle nach 5 min Leerlauf aus dem RAM
    };
  };

  # Ordner gehoeren dem immich-Benutzer; Dienst startet nur mit eingehaengtem Pool
  systemd.tmpfiles.rules = [
    "d ${media} 0750 immich immich -"
    "d ${thumbs} 0750 immich immich -"
  ];
  systemd.services.immich-server = {
    unitConfig.RequiresMountsFor = [ media "${media}/thumbs" ];
    # tmpfiles laeuft vor dem Einhaengen des Datasets; der eingehaengte Ordner gehoert sonst root
    # und Immich bricht mit EACCES ab. "+" = als root vor dem Start.
    serviceConfig.ExecStartPre = [ "+${pkgs.coreutils}/bin/install -d -m 0750 -o immich -g immich ${media}" ];
  };

  services.sanoid.datasets.${dataset} = {
    hourly = 0;
    daily = 30;
    monthly = 12;
    yearly = 0;
    autosnap = true;
    autoprune = true;
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ 2283 ];
}
