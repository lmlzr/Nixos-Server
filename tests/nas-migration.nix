# VM-Test: Umzug TrueNAS-Pool TB1 -> tank, Samba-Rechte, Snapshots, Plattenausfall.
# Ausfuehren: nix build .#checks.x86_64-linux.nas-migration -L
{ pkgs }:
let
  repo = ../.;
in
pkgs.testers.runNixOSTest {
  name = "nas-migration";
  nodes.machine = { config, lib, pkgs, ... }: {
    imports = [
      "${repo}/modules/storage-paths.nix"
      "${repo}/Hardware/storage.nix"
      "${repo}/modules/zfs-snapshots.nix"
      "${repo}/modules/storage-monitoring.nix"
      "${repo}/modules/backup.nix"
      "${repo}/modules/links.nix"
      "${repo}/services/smb.nix"
      "${repo}/users/lmlzr.nix"
      "${repo}/users/dbglas.nix"
    ];
    services.jellyfin.enable = true;
    users.users.jellyfin.extraGroups = [ "media" ];

    # Nur fuer die Test-VM: virtuelle Platten ohne Seriennummer und ohne SMART
    virtualisation.emptyDiskImages = [ 2048 2048 ];
    virtualisation.memorySize = 2048;
    boot.zfs.devNodes = "/dev/disk/by-path";
    # Test-Framework ersetzt fileSystems durch virtualisation.fileSystems
    virtualisation.fileSystems = config.nas.mounts;
    services.smartd.enable = lib.mkForce false;
    nas.lanInterface = "eth1";
    environment.systemPackages = [ pkgs.samba ];
  };

  testScript = ''
    def smb(user, cmd, share):
        return f"smbclient //127.0.0.1/{share} -U {user}%Geheim123 -c '{cmd}'"

    machine.wait_for_unit("multi-user.target")

    with subtest("Ohne Pool: System bootet, Dienste mit Pool-Daten starten nicht"):
        machine.fail("systemctl is-active jellyfin")
        machine.succeed("systemctl is-active sshd || true")

    with subtest("TrueNAS-Pool TB1 nachbauen (Mirror) und exportieren"):
        machine.succeed(
            "zpool create -o ashift=12 -O compression=lz4 -O atime=off -m /mnt/TB1 TB1 mirror /dev/vdb /dev/vdc",
            "mkdir -p /mnt/TB1/psycho/Fotos /mnt/TB1/dbglas/Daten /mnt/TB1/jellyfin/Movies/Film1 /mnt/TB1/jellyfin/TV/Serie1 /mnt/TB1/jellyfin/lancache /mnt/TB1/jellyfin/Music /mnt/TB1/server/zeug /mnt/TB1/iocage",
            "dd if=/dev/urandom of=/mnt/TB1/jellyfin/Movies/Film1/film.mkv bs=1M count=40",
            "dd if=/dev/urandom of=/mnt/TB1/jellyfin/TV/Serie1/folge.mkv bs=1M count=30",
            "dd if=/dev/urandom of=/mnt/TB1/jellyfin/lancache/cache bs=1M count=20",
            "echo foto > /mnt/TB1/psycho/Fotos/urlaub.jpg && echo daten > /mnt/TB1/dbglas/Daten/a.txt && echo zeug > /mnt/TB1/server/zeug/x",
            "chown -R 1000:1000 /mnt/TB1/psycho && chown -R 1003:1003 /mnt/TB1/dbglas && chown -R 1001:1001 /mnt/TB1/jellyfin && chown -R 1002:1002 /mnt/TB1/server",
            "zpool export TB1",
        )

    with subtest("Runbook Schritt: Import mit Umbenennung, Eigenschaften, Datasets"):
        machine.succeed(
            "zpool import -d /dev/disk/by-path -f -N TB1 tank",
            "zfs set mountpoint=legacy atime=off xattr=sa acltype=posixacl tank",
            "zfs create -o mountpoint=legacy -o recordsize=1M tank/media",
            "zfs create -o mountpoint=legacy -o utf8only=on -o normalization=formD tank/share",
            "zfs create -o mountpoint=legacy tank/services",
            "zfs create -o mountpoint=legacy -o recordsize=1M -o quota=200M tank/lancache",
            "zfs create -o mountpoint=none -o refreservation=100M tank/reserved",
        )
        # Runbook: danach neu starten; Pool wird automatisch importiert und eingehaengt
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("mountpoint -q /mnt/tank/media && mountpoint -q /mnt/tank/share && mountpoint -q /mnt/tank/services")
        machine.succeed("zpool list -H -o name | grep -x tank")
        machine.succeed("test -d /mnt/tank/services/jellyfin")
        machine.succeed("stat -c '%a %U %G' /mnt/tank/media | grep '2775 root media'")
        machine.succeed("stat -c '%a %U %G' /mnt/tank/share/dbglas | grep '700 dbglas dbglas'")

    with subtest("Runbook Schritt: Ordner fuer Ordner umziehen"):
        machine.succeed(
            "rm -rf /mnt/tank/jellyfin/lancache",
            "rsync -aHAX /mnt/tank/dbglas/ /mnt/tank/share/dbglas/ && diff -r /mnt/tank/dbglas /mnt/tank/share/dbglas && rm -rf /mnt/tank/dbglas",
            "rsync -aHAX /mnt/tank/server/ /mnt/tank/services/ && diff -r /mnt/tank/server/zeug /mnt/tank/services/zeug && rm -rf /mnt/tank/server",
            "rsync -aHAX /mnt/tank/psycho/ /mnt/tank/share/lmlzr/ && diff -r /mnt/tank/psycho /mnt/tank/share/lmlzr && rm -rf /mnt/tank/psycho",
            "for d in Music Movies TV; do rsync -aHAX /mnt/tank/jellyfin/$d/ /mnt/tank/media/$d/ && diff -r /mnt/tank/jellyfin/$d /mnt/tank/media/$d && rm -rf /mnt/tank/jellyfin/$d; done",
            "rmdir /mnt/tank/jellyfin",
            # Rechte gezielt pro Dataset, kein chmod 777
            "chown -R root:media /mnt/tank/media/Music /mnt/tank/media/Movies /mnt/tank/media/TV",
            "find /mnt/tank/media/Music /mnt/tank/media/Movies /mnt/tank/media/TV -type d -exec chmod 2775 {} +",
            "find /mnt/tank/media/Music /mnt/tank/media/Movies /mnt/tank/media/TV -type f -exec chmod 664 {} +",
            "chown -R lmlzr:users /mnt/tank/share/lmlzr",
        )
        machine.succeed("stat -c '%u' /mnt/tank/share/dbglas/Daten/a.txt | grep 1003")
        machine.succeed("ls /mnt/tank | sort | tr '\\n' ' ' | grep -x 'iocage lancache media services share '")

    with subtest("Neustart: Pool wird automatisch importiert, alles haengt, Dienste laufen"):
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        for m in ["/mnt/tank", "/mnt/tank/media", "/mnt/tank/share", "/mnt/tank/services", "/mnt/tank/lancache", "/var/lib/jellyfin"]:
            machine.succeed(f"mountpoint -q {m}")
        machine.wait_for_unit("jellyfin.service")
        machine.succeed("sudo -u jellyfin cat /mnt/tank/media/Movies/Film1/film.mkv > /dev/null")
        machine.succeed("cat /sys/module/zfs/parameters/zfs_arc_max | grep 21474836480")

    with subtest("Samba: Rechte wie geplant"):
        machine.wait_for_unit("samba-smbd.service")
        machine.succeed("(echo Geheim123; echo Geheim123) | smbpasswd -s -a lmlzr")
        machine.succeed("(echo Geheim123; echo Geheim123) | smbpasswd -s -a dbglas")
        out = machine.succeed("smbclient -L //127.0.0.1 -U lmlzr%Geheim123 -g")
        for s in ["share", "lmlzr", "dbglas", "media"]:
            assert f"Disk|{s}|" in out, out
        out = machine.succeed("smbclient -L //127.0.0.1 -U dbglas%Geheim123 -g")
        assert "Disk|dbglas|" in out and "Disk|media|" not in out and "Disk|share|" not in out and "Disk|lmlzr|" not in out, out
        machine.fail("smbclient -L //127.0.0.1 -N")
        machine.fail("smbclient //127.0.0.1/media -N -c ls")
        # dbglas: eigener Bereich ja, Medien und share nein
        machine.succeed("echo x > /tmp/f.txt")
        machine.succeed(smb("dbglas", "put /tmp/f.txt von-dbglas.txt", "dbglas"))
        machine.fail(smb("dbglas", "ls", "media"))
        machine.fail(smb("dbglas", "ls", "share"))
        machine.fail(smb("dbglas", "ls", "lmlzr"))
        # lmlzr: Admin ueberall; Dateien in dbglas gehoeren dbglas, in media der Gruppe media
        machine.succeed(smb("lmlzr", "put /tmp/f.txt von-lmlzr.txt", "dbglas"))
        machine.succeed("stat -c '%U' /mnt/tank/share/dbglas/von-lmlzr.txt | grep dbglas")
        machine.succeed(smb("lmlzr", "put /tmp/f.txt neu.txt", "media"))
        machine.succeed("stat -c '%G' /mnt/tank/media/neu.txt | grep media")
        machine.succeed(smb("lmlzr", "ls Fotos/*", "lmlzr"))
        # Protokoll aelter als SMB2 abgelehnt
        machine.fail("smbclient -L //127.0.0.1 -U lmlzr%Geheim123 -m NT1")

    with subtest("Snapshots"):
        # sanoid merkt sich die Dataset-Liste 20 min; beim ersten Boot gab es noch keinen Pool
        machine.succeed("rm -rf /var/cache/private/sanoid/* && systemctl start sanoid.service")
        machine.wait_until_succeeds("zfs list -H -t snapshot -o name | grep -q tank/services@", timeout=60)
        snaps = machine.succeed("zfs list -H -t snapshot -o name")
        for ds in ["tank/media@", "tank/share@", "tank/services@"]:
            assert ds in snaps, snaps
        assert "tank/lancache@" not in snaps and "\ntank@" not in ("\n" + snaps), snaps
        # Wiederherstellen aus Snapshot
        machine.succeed("rm /mnt/tank/share/lmlzr/Fotos/urlaub.jpg")
        machine.succeed("cp /mnt/tank/share/.zfs/snapshot/$(ls /mnt/tank/share/.zfs/snapshot | head -1)/lmlzr/Fotos/urlaub.jpg /mnt/tank/share/lmlzr/Fotos/")

    with subtest("Lancache-Quota greift"):
        machine.fail("dd if=/dev/urandom of=/mnt/tank/lancache/zu-gross bs=1M count=300")

    with subtest("Plattenausfall: Pool laeuft eingeschraenkt weiter, Gesundheitscheck meldet es"):
        machine.succeed("systemctl start zfs-health.service")
        disk = machine.succeed("zpool status -P tank | grep -o '/dev/disk/by-path/[^ ]*' | tail -1").strip()
        machine.succeed(f"zpool offline tank {disk}")
        machine.succeed("zpool status tank | grep DEGRADED")
        machine.succeed("cat /mnt/tank/media/Movies/Film1/film.mkv > /dev/null")
        machine.fail("systemctl start zfs-health.service")
        machine.succeed(f"zpool online tank {disk}")
        machine.wait_until_succeeds("zpool status -x tank | grep healthy")
        machine.succeed("systemctl start zfs-health.service")

  '';
}
