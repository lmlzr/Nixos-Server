{ config, lib, ... }:

# Zentrale Pfade des NAS. Andere Module (links.nix, lancache, arr-stack, smb, ...)
# lesen diese Werte, statt Pfade fest einzutragen.
let
  cfg = config.nas;
in
{
  options.nas = {
    pool = lib.mkOption {
      type = lib.types.str;
      default = "tank";
      description = "Name des ZFS-Pools.";
    };

    root = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/${cfg.pool}";
      description = "Mountpoint des Pool-Root-Datasets.";
    };

    mediaDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.root}/media";
      description = "Dataset <pool>/media: Filme, Serien, Musik usw. Downloads liegen hier mit drin (Hardlinks).";
    };

    shareDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.root}/share";
      description = "Dataset <pool>/share: persoenliche und allgemeine Dateien.";
    };

    fastPool = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "fast";
      description = ''
        ZFS-Pool auf SSD fuer die Dienst-Daten, damit die HDDs in den Spindown gehen koennen.
        null = Dienst-Daten liegen auf dem HDD-Pool (z. B. Test-VM).
      '';
    };

    servicesDataset = lib.mkOption {
      type = lib.types.str;
      default = if cfg.fastPool != null then "${cfg.fastPool}/services" else "${cfg.pool}/services";
      description = "Dataset mit den Daten der Dienste.";
    };

    servicesDir = lib.mkOption {
      type = lib.types.str;
      default = if cfg.fastPool != null then "/mnt/${cfg.fastPool}/services" else "${cfg.root}/services";
      description = "Mountpoint von servicesDataset: Daten der Dienste (per Bind-Mount nach /var/lib).";
    };

    servicesBackupDataset = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.pool}/backup/services";
      description = "Naechtliche Kopie von servicesDataset auf dem HDD-Pool (nur mit fastPool).";
    };

    lancacheDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.root}/lancache";
      description = "Dataset <pool>/lancache: wegwerfbarer Spiele-Cache mit Quota.";
    };

    mounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      internal = true;
      description = "Datasets und Bind-Mounts des NAS; werden zu fileSystems (getrennt, damit Tests sie uebernehmen koennen).";
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "enp3s0";
      description = "LAN-Schnittstelle. Nur hier werden Samba-Ports geoeffnet. Auf neuer Hardware mit `ip link` pruefen.";
    };
  };

  config.fileSystems = cfg.mounts;
}
