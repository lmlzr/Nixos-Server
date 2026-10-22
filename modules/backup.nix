{ config, lib, ... }:

# Vorlage fuer das externe Backup (Konzept folgt). Standardmaessig aus.
# Ein Mirror schuetzt nur vor dem Ausfall EINER Platte, nicht vor Loeschen,
# Ausfall beider Platten, Brand oder Diebstahl.
let
  cfg = config.nas.backup;
in
{
  options.nas.backup = {
    enable = lib.mkEnableOption "Replikation wichtiger Datasets per syncoid";

    target = lib.mkOption {
      type = lib.types.str;
      example = "backup@backuphost:backuppool/neotokyo";
      description = "Ziel fuer syncoid (Benutzer@Host:Pool/Dataset).";
    };

    datasets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${config.nas.pool}/share" "${config.nas.pool}/services" ];
      description = "Zu sichernde Datasets. Medien bewusst nicht (wiederbeschaffbar).";
    };

    sshKey = lib.mkOption {
      type = lib.types.str;
      default = "/etc/secrets/backup-ssh-key";
    };
  };

  config = lib.mkIf cfg.enable {
    services.syncoid = {
      enable = true;
      interval = "daily";
      sshKey = cfg.sshKey;
      commands = lib.listToAttrs (map (ds: {
        name = ds;
        value = {
          target = "${cfg.target}/${lib.last (lib.splitString "/" ds)}";
          extraArgs = [ "--no-sync-snap" ];
        };
      }) cfg.datasets);
    };
  };
}
