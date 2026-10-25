{ config, lib, pkgs, ... }:

# ZFS-Pool "tank": Mirror aus 2x 16 TB (wwn-0x5000c500e7ab0441, wwn-0x5000c500e7aafd88).
# ZFS-Pool "fast": WD Blue SN580 1 TB (NVMe, einzeln) nur fuer die Dienst-Daten,
# naechtlich per syncoid nach tank/backup/services gesichert.
# Ersetzt Hardware/hdds.nix. Pools und Datasets werden NICHT automatisch angelegt,
# siehe docs/NAS-Migration.md und docs/SSD-SERVICES.md.
let
  cfg = config.nas;

  # Dataset -> Mountpoint. Alle Datasets haben mountpoint=legacy, NixOS haengt sie ein.
  datasets = {
    ${cfg.root} = cfg.pool;
    ${cfg.mediaDir} = "${cfg.pool}/media";
    ${cfg.shareDir} = "${cfg.pool}/share";
    ${cfg.servicesDir} = cfg.servicesDataset;
    ${cfg.lancacheDir} = "${cfg.pool}/lancache";
  };

  dataMounts = lib.attrNames datasets;

  # Dienste, die ohne Pool nicht starten duerfen (sonst schreiben sie auf die Systemplatte)
  mountDependents = lib.filterAttrs (name: v: v.enable) {
    jellyfin = { enable = config.services.jellyfin.enable; paths = [ cfg.mediaDir ]; };
    sonarr = { enable = config.services.sonarr.enable; paths = [ cfg.mediaDir ]; };
    radarr = { enable = config.services.radarr.enable; paths = [ cfg.mediaDir ]; };
    lidarr = { enable = config.services.lidarr.enable; paths = [ cfg.mediaDir ]; };
    qbittorrent = { enable = config.services.qbittorrent.enable; paths = [ cfg.mediaDir ]; };
    samba-smbd = { enable = config.services.samba.enable; paths = [ cfg.mediaDir cfg.shareDir ]; };
    nginx = { enable = config.services.lancache.enable or false; paths = [ cfg.lancacheDir ]; };
  };
in
{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  # Muss gleich bleiben, sonst importiert NixOS den Pool nicht automatisch
  networking.hostId = "99f03424";

  # ARC (RAM-Lesecache) begrenzen: 20 GiB von 48 GB, Rest fuer Dienste und Gameserver
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_max=${toString (20 * 1024 * 1024 * 1024)}
  '';

  # nofail: fehlt der Pool, bootet das System trotzdem und bleibt per SSH erreichbar.
  # Die abhaengigen Dienste starten dann nicht (RequiresMountsFor unten).
  nas.mounts = lib.mapAttrs (mountpoint: dataset: {
    device = dataset;
    fsType = "zfs";
    options = [ "nofail" ];
  }) datasets;

  users.groups.media = { };

  systemd.services = lib.mapAttrs (name: dep: {
    unitConfig.RequiresMountsFor = dep.paths;
  }) mountDependents // {
  # Oberste Ordner mit Besitzer anlegen, nur wenn die Datasets wirklich eingehaengt sind.
  # Nicht rekursiv: bestehende Dateien werden nicht angefasst.
  nas-dirs = {
    description = "NAS: Grundordner auf dem Pool anlegen";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    before = map (name: "${name}.service") (lib.attrNames mountDependents);
    unitConfig = {
      RequiresMountsFor = [ cfg.mediaDir cfg.shareDir cfg.lancacheDir ];
      ConditionPathIsMountPoint = cfg.mediaDir;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 2775 -o root -g media ${cfg.mediaDir}
      install -d -m 2775 -o root -g media ${cfg.mediaDir}/downloads
      install -d -m 0751 -o lmlzr -g users ${cfg.shareDir}
      install -d -m 0750 -o lmlzr -g users ${cfg.shareDir}/lmlzr
      install -d -m 0700 -o dbglas -g dbglas ${cfg.shareDir}/dbglas
    '' + lib.optionalString (config.services.lancache.enable or false) ''
      install -d -m 0750 -o ${config.services.nginx.user} -g ${config.services.nginx.group} ${cfg.lancacheDir}
    '';
  };
  };

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = [ cfg.pool ] ++ lib.optional (cfg.fastPool != null) cfg.fastPool;
  };

  # Naechtliche Kopie der Dienst-Daten von der SSD auf den HDD-Pool. Nutzt die
  # sanoid-Snapshots (kein eigener Sync-Snapshot); weckt die HDDs einmal pro Nacht.
  # Ziel wird nicht eingehaengt (mountpoint=legacy von tank geerbt, -u beim Empfang).
  services.syncoid = lib.mkIf (cfg.fastPool != null) {
    enable = true;
    interval = lib.mkDefault "*-*-* 03:30:00";
    commands.${cfg.servicesDataset} = {
      target = cfg.servicesBackupDataset;
      recvOptions = "u";
      extraArgs = [ "--no-sync-snap" ];
    };
  };

  environment.systemPackages = with pkgs; [
    smartmontools
    rsync
  ];
}
