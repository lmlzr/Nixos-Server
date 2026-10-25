# Dienst-Daten auf die NVMe-SSD (Pool `fast`)

Ziel: Datenbanken, Logs und Configs der Dienste schreiben nicht mehr auf die HDDs,
damit `tank` in den Spindown gehen kann. Die SSD ist einzeln (kein Mirror); jede Nacht
um 03:30 kopiert syncoid `fast/services` nach `tank/backup/services`.

| | vorher | nachher |
|---|---|---|
| Dataset | `tank/services` | `fast/services` |
| Mountpoint | `/mnt/tank/services` | `/mnt/fast/services` |
| Snapshots | täglich (14), monatlich (3) | stündlich (24), täglich (14), monatlich (3) |
| Kopie | – | `tank/backup/services`, täglich (30), monatlich (6) |

Die Config (`modules/storage-paths.nix`: `nas.fastPool`, `Hardware/storage.nix`,
`modules/zfs-snapshots.nix`) ist schon umgestellt; die Schritte unten sind einmalig.

## 1. NVMe leeren und Pool anlegen

Auf der NVMe liegen noch die LVM-Volumes der alten Proxmox-VMs (101–104).
**Schritt 1 löscht alles darauf.**

```bash
NVME=/dev/disk/by-id/nvme-WD_Blue_SN580_1TB_2342BT412250
sudo vgchange -an WD_1TB
sudo wipefs -a "$NVME"

sudo zpool create -o ashift=12 -o autotrim=on \
  -O compression=zstd -O atime=off -O xattr=sa -O acltype=posixacl -O dnodesize=auto \
  -O mountpoint=none fast "$NVME"
```

## 2. Dienste stoppen und Daten kopieren

```bash
sudo systemctl stop docker.service docker.socket jellyfin audiobookshelf stirling-pdf \
  sonarr radarr lidarr prowlarr seerr qbittorrent mysql wings syncthing 'phpfpm-*'

sudo zfs snapshot tank/services@umzug-ssd
sudo zfs send tank/services@umzug-ssd | sudo zfs recv -u -o mountpoint=legacy fast/services
zfs list -o name,used fast/services tank/services   # USED etwa gleich
```

## 3. Neue Config aktivieren

```bash
cd ~/Nixos-Server
sudo nixos-rebuild boot --flake .#neotokyo
sudo reboot
```

Nach dem Neustart:

```bash
findmnt /var/lib/jellyfin         # SOURCE: fast/services[/jellyfin]
systemctl --failed
```

## 4. Altes Dataset wird die Backup-Kopie

`tank/services` hat denselben Snapshot `@umzug-ssd` wie `fast/services`, deshalb überträgt
syncoid danach nur noch Änderungen.

```bash
sudo zfs create -o canmount=off tank/backup        # erbt mountpoint=legacy, wird nie eingehängt
sudo zfs rename tank/services tank/backup/services
sudo systemctl start syncoid-fast-services.service
journalctl -u syncoid-fast-services -n 20
```

## Wiederherstellen

Einzelne Dateien: aus `/mnt/fast/services/.zfs/snapshot/<snapshot>/…` kopieren.

SSD defekt: neue SSD, Pool wie in Schritt 1 anlegen, dann

```bash
sudo zfs send -R tank/backup/services@<neuester> | sudo zfs recv -u -o mountpoint=legacy fast/services
```

Notfalls ohne SSD: in `configuration.nix` `nas.fastPool = null;` und
`nas.servicesDataset = "tank/backup/services";` setzen.
