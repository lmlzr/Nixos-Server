{ config, lib, pkgs, ... }:

# Empfaenger fuer das naechtliche Backup von /docker der VM vmdocker (10.0.0.3).
# Die VM schiebt per rsync (Cron 04:00 als root, Container kurz angehalten) ueber SSH als
# Benutzer vmdocker-backup; rrsync sperrt den Schluessel auf das Zielverzeichnis.
# Besitzer/Rechte der Dateien speichert rsync --fake-super in xattrs (Dataset: xattr=sa).
# Aeltere Staende: sanoid-Snapshots (taeglich 03:25, also vor dem naechsten Lauf).
#
# Dataset einmalig anlegen:
#   sudo zfs create -o mountpoint=legacy -o xattr=sa -o compression=zstd tank/backup/vmdocker
# Wiederherstellen (auf der VM als root):
#   rsync -aHX --numeric-ids -M--fake-super -e "ssh -i /root/.ssh/backup_neotokyo" \
#     vmdocker-backup@10.0.0.5:docker/ /docker/
let
  cfg = config.nas;
  dataset = "${cfg.pool}/backup/vmdocker";
  dir = "${cfg.root}/backup/vmdocker";
  user = "vmdocker-backup";
  pubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFWpYLguJAoGDqJA6s9nzAOXTVlD5whlWHqN72qd/min vmdocker-backup";
in
{
  nas.mounts.${dir} = {
    device = dataset;
    fsType = "zfs";
    options = [ "nofail" ];
  };

  users.users.${user} = {
    isSystemUser = true;
    group = user;
    home = "/var/empty";
    shell = pkgs.bashInteractive; # sshd braucht eine Shell fuer command=
    openssh.authorizedKeys.keys = [
      ''restrict,from="10.0.0.3",command="${pkgs.rrsync}/bin/rrsync ${dir}" ${pubKey}''
    ];
  };
  users.groups.${user} = { };

  services.sanoid.datasets.${dataset} = {
    hourly = 0;
    daily = 30;
    monthly = 6;
    yearly = 0;
    autosnap = true;
    autoprune = true;
  };

  systemd.services.vmdocker-backup-dir = {
    description = "Backup vmdocker: Zielverzeichnis vorbereiten";
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      RequiresMountsFor = [ dir ];
      ConditionPathIsMountPoint = dir;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 0750 -o ${user} -g ${user} ${dir}/docker
    '';
  };

  # Wachhund: Die VM legt nach jedem erfolgreichen Lauf .backup-ok ab. Ist die Datei
  # aelter als 26 h (oder fehlt), schlaegt der Dienst fehl und notify-mail@ meldet es.
  # 06:30: nach dem Backup-Fenster; liest nur Metadaten (L2ARC), weckt die HDDs i. d. R. nicht.
  systemd.services.vmdocker-backup-check = {
    description = "Backup vmdocker: letzter erfolgreicher Lauf juenger als 26 h?";
    onFailure = [ "notify-mail@%n.service" ];
    unitConfig.RequiresMountsFor = [ dir ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.coreutils pkgs.findutils ];
    script = ''
      ok=${dir}/docker/.backup-ok
      if [ -z "$(find "$ok" -mmin -1560 2>/dev/null)" ]; then
        echo "Kein erfolgreiches Backup von vmdocker in den letzten 26 Stunden (letztes: $(date -r "$ok" 2>/dev/null || echo nie))." >&2
        exit 1
      fi
      echo "Letztes Backup von vmdocker: $(date -r "$ok")"
    '';
  };
  systemd.timers.vmdocker-backup-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:30:00";
      Persistent = true;
    };
  };
}
