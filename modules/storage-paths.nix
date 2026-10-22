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

    servicesDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.root}/services";
      description = "Dataset <pool>/services: Daten der Dienste (per Bind-Mount nach /var/lib).";
    };

    lancacheDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.root}/lancache";
      description = "Dataset <pool>/lancache: wegwerfbarer Spiele-Cache mit Quota.";
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "enp3s0";
      description = "LAN-Schnittstelle. Nur hier werden Samba-Ports geoeffnet. Auf neuer Hardware mit `ip link` pruefen.";
    };
  };
}
