# Umzug TrueNAS → NixOS: Befehle zum Abarbeiten

Hintergrund, Zielstruktur, Rückweg und Wartung stehen in [NAS-Migration.md](NAS-Migration.md).
Diese Datei enthält nur die Befehle – vor und nach dem Umzug.

**So funktioniert es:**

- Jeder Ordner hat einen eigenen Block. Die **Reihenfolge der Ordner ist frei**.
- **Vor dem Umzug** (TrueNAS läuft noch) kann jeder Ordner **vorab kopiert** werden – das ist
  freiwillig und spart am Umzugstag Zeit. Die Originale bleiben dabei liegen.
- **Nach dem Umzug** (NixOS) wird jeder Ordner mit **demselben Befehl** abgeglichen – egal, ob er
  vorher kopiert wurde (dann wird nur nachgezogen, was sich geändert hat) oder nicht (dann wird
  alles kopiert).
- Gelöscht wird eine Quelle **erst, wenn die Prüfung `OK` meldet**.
- Bis zum ersten Löschen unter NixOS ist alles umkehrbar (zurück zu TrueNAS, siehe NAS-Migration.md).

| Ordner | Größe | Ziel |
|---|---|---|
| `dbglas` | 46 GB | `share/dbglas` |
| `server` | 75 GB | `services/alt-truenas` |
| `psycho` | 892 GB | `share/lmlzr` |
| `jellyfin/Books` | 2,5 GB | `media/Books` |
| `jellyfin/Comics` | < 1 GB | `media/Comics` |
| `jellyfin/Music` | 26 GB | `media/Music` |
| `jellyfin/Manga` | 48 GB | `media/Manga` |
| `jellyfin/Audiobooks` | 136 GB | `media/Audiobooks` |
| `jellyfin/Movies` | 1,9 TB | `media/Movies` |
| `jellyfin/TV` | 3,3 TB | `media/TV` |
| `jellyfin/lancache` | 1,3 TB | wird gelöscht (laut NAS-Migration.md bereits erledigt) |

---

# Teil A – Vor dem Umzug (in TrueNAS)

Alle Befehle in der **TrueNAS-Shell als root** (*System → Shell* oder SSH).
Die Warnung von TrueNAS zu Shell-Befehlen ist hier unkritisch.

## A1. Sicherheit zuerst

- Externes Backup von `psycho`, `dbglas`, `server` (USB-Platte o. Ä.) – fertig und geprüft?
- Pool gesund?
  ```bash
  zpool status -v TB1
  ```
  Erwartet: `state: ONLINE`, `errors: No known data errors`.
- SMART-Langtest (auf dem **Proxmox-Host**, nicht in TrueNAS):
  ```bash
  smartctl -t long /dev/disk/by-id/wwn-0x5000c500e7ab0441; smartctl -t long /dev/disk/by-id/wwn-0x5000c500e7aafd88
  ```
  Ergebnis nach vielen Stunden: `smartctl -l selftest /dev/disk/by-id/wwn-0x5000c500e7ab0441`
  → `Completed without error`.

## A2. Sitzung, die Verbindungsabbrüche übersteht

```bash
tmux new -s umzug
```
Wieder verbinden: `tmux attach -t umzug` · Abkoppeln ohne Abbruch: `Strg+B`, dann `D`.

## A3. Datasets anlegen (einmalig, vor dem ersten Vorab-Kopieren)

```bash
zfs create -o recordsize=1M TB1/media
zfs create -o utf8only=on -o normalization=formD TB1/share
zfs create TB1/services
zfs create -o recordsize=1M -o quota=2T TB1/lancache
zfs list -r TB1
```
Erwartet: `TB1/media`, `TB1/share`, `TB1/services`, `TB1/lancache` unter `/mnt/TB1/…`.

Wer gar nichts vorab kopieren will, kann A3 überspringen – die Datasets werden dann in B2 angelegt.

## A4. Platz prüfen (vor jedem großen Ordner)

```bash
zfs list -o name,used,avail TB1
```
`AVAIL` muss deutlich größer sein als der Ordner (Tabelle oben). Beim Vorab-Kopieren bleiben die
Originale liegen, der Platz wird also doppelt belegt.

## A5. Ordner vorab kopieren (freiwillig, beliebige Reihenfolge)

Pro Ordner: kopieren, dann prüfen. `OK` = Kopie vollständig. Ändern sich danach noch Dateien
(z. B. neue Downloads), ist das egal – das wird nach dem Umzug abgeglichen.

### dbglas
```bash
rsync -aH --info=progress2 /mnt/TB1/dbglas/ /mnt/TB1/share/dbglas/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/dbglas/ /mnt/TB1/share/dbglas/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### server
```bash
rsync -aH --info=progress2 /mnt/TB1/server/ /mnt/TB1/services/alt-truenas/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/server/ /mnt/TB1/services/alt-truenas/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### psycho
```bash
rsync -aH --info=progress2 /mnt/TB1/psycho/ /mnt/TB1/share/lmlzr/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/psycho/ /mnt/TB1/share/lmlzr/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### Books
```bash
rsync -aH --info=progress2 /mnt/TB1/jellyfin/Books/ /mnt/TB1/media/Books/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/jellyfin/Books/ /mnt/TB1/media/Books/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### Comics
```bash
rsync -aH --info=progress2 /mnt/TB1/jellyfin/Comics/ /mnt/TB1/media/Comics/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/jellyfin/Comics/ /mnt/TB1/media/Comics/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### Music
```bash
rsync -aH --info=progress2 /mnt/TB1/jellyfin/Music/ /mnt/TB1/media/Music/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/jellyfin/Music/ /mnt/TB1/media/Music/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### Manga
```bash
rsync -aH --info=progress2 /mnt/TB1/jellyfin/Manga/ /mnt/TB1/media/Manga/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/jellyfin/Manga/ /mnt/TB1/media/Manga/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### Audiobooks
```bash
rsync -aH --info=progress2 /mnt/TB1/jellyfin/Audiobooks/ /mnt/TB1/media/Audiobooks/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/jellyfin/Audiobooks/ /mnt/TB1/media/Audiobooks/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### Movies (1,9 TB – mehrere Stunden)
```bash
rsync -aH --info=progress2 /mnt/TB1/jellyfin/Movies/ /mnt/TB1/media/Movies/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/jellyfin/Movies/ /mnt/TB1/media/Movies/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### TV (3,3 TB – grob 6–8 Stunden)
```bash
rsync -aH --info=progress2 /mnt/TB1/jellyfin/TV/ /mnt/TB1/media/TV/
n=$(rsync -aH --dry-run --itemize-changes /mnt/TB1/jellyfin/TV/ /mnt/TB1/media/TV/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
```

### lancache
Nur falls der Ordner noch existiert und der alte Lancache gestoppt ist:
```bash
rm -rf /mnt/TB1/jellyfin/lancache
```

## A6. TrueNAS abschalten (Umzugstag)

1. In TrueNAS alle Aufgaben aus: *Periodic Snapshot Tasks*, *Replication*, *Scrub Tasks*,
   *Cloud Sync*, *Rsync Tasks*.
2. Dienste stoppen, die auf `TB1` schreiben (Docker-VM, Jellyfin, Downloads).
3. TrueNAS-VM **herunterfahren**. **Nicht** „Export/Disconnect“ benutzen.
4. **Kein `zpool upgrade`** – sonst gibt es keinen Rückweg zu TrueNAS.
5. Proxmox-Host herunterfahren, **16-TB-Platten abstecken**, NixOS installieren
   (siehe NAS-Migration.md, Phase B), Platten wieder anschließen.

---

# Teil B – Nach dem Umzug (unter NixOS)

## B1. Pool übernehmen

```bash
sudo zpool import
```
Erwartet: `pool: TB1`, `state: ONLINE`, `mirror-0` mit zwei Platten.
```bash
sudo zpool import -f -N TB1 tank
sudo zpool status tank
```

## B2. Datasets anlegen (nur die, die noch fehlen) und Eigenschaften setzen

Was gibt es schon?
```bash
sudo zfs list -r tank
```
Nur die **fehlenden** anlegen (wurde A3 gemacht, gibt es alle vier schon):
```bash
sudo zfs create -o mountpoint=legacy -o recordsize=1M tank/media
sudo zfs create -o mountpoint=legacy -o utf8only=on -o normalization=formD tank/share
sudo zfs create -o mountpoint=legacy tank/services
sudo zfs create -o mountpoint=legacy -o recordsize=1M -o quota=2T tank/lancache
```
Eigenschaften für **alle** setzen (nötig, weil TrueNAS eigene Werte vergibt):
```bash
for ds in tank tank/media tank/share tank/services tank/lancache; do sudo zfs set mountpoint=legacy atime=off xattr=sa acltype=posixacl $ds; done
sudo zfs get -r -o name,property,value mountpoint,acltype,xattr tank | grep -v iocage
```
Erwartet: überall `legacy`, `posix` und `sa`.

Platzreserve:
```bash
sudo zfs create -o mountpoint=none -o refreservation=500G tank/reserved
```

## B3. Neu starten und prüfen

```bash
sudo reboot
```
```bash
findmnt -t zfs; systemctl --failed
```
Erwartet: `/mnt/tank`, `/mnt/tank/media`, `/share`, `/services`, `/lancache` eingehängt,
keine fehlgeschlagenen Units. Die alten Ordner liegen jetzt unter `/mnt/tank/`.

## B4. Dienste stoppen, die schreiben könnten

```bash
sudo systemctl stop jellyfin sonarr radarr lidarr qbittorrent samba-smbd
```
```bash
tmux new -s umzug
```
(`tmux` fehlt? `nix-shell -p tmux --run "tmux new -s umzug"`)

## B5. Ordner abgleichen, prüfen, Quelle löschen (beliebige Reihenfolge)

Pro Ordner drei Schritte: **abgleichen** → **prüfen** → nur bei `OK` **Quelle löschen**.
Der Abgleich kopiert alles, was im Ziel fehlt oder anders ist, und entfernt im Ziel, was es in
der Quelle nicht mehr gibt.

### dbglas
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/dbglas/ /mnt/tank/share/dbglas/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/dbglas/ /mnt/tank/share/dbglas/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/dbglas
```

### server
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/server/ /mnt/tank/services/alt-truenas/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/server/ /mnt/tank/services/alt-truenas/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/server
```

### psycho
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/psycho/ /mnt/tank/share/lmlzr/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/psycho/ /mnt/tank/share/lmlzr/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/psycho
sudo chown -R lmlzr:users /mnt/tank/share/lmlzr
```

### Books
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/jellyfin/Books/ /mnt/tank/media/Books/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/jellyfin/Books/ /mnt/tank/media/Books/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/jellyfin/Books
```

### Comics
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/jellyfin/Comics/ /mnt/tank/media/Comics/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/jellyfin/Comics/ /mnt/tank/media/Comics/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/jellyfin/Comics
```

### Music
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/jellyfin/Music/ /mnt/tank/media/Music/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/jellyfin/Music/ /mnt/tank/media/Music/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/jellyfin/Music
```

### Manga
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/jellyfin/Manga/ /mnt/tank/media/Manga/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/jellyfin/Manga/ /mnt/tank/media/Manga/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/jellyfin/Manga
```

### Audiobooks
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/jellyfin/Audiobooks/ /mnt/tank/media/Audiobooks/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/jellyfin/Audiobooks/ /mnt/tank/media/Audiobooks/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/jellyfin/Audiobooks
```

### Movies
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/jellyfin/Movies/ /mnt/tank/media/Movies/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/jellyfin/Movies/ /mnt/tank/media/Movies/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/jellyfin/Movies
```

### TV
```bash
sudo rsync -aH --delete --info=progress2 /mnt/tank/jellyfin/TV/ /mnt/tank/media/TV/
n=$(sudo rsync -aH --dry-run --itemize-changes /mnt/tank/jellyfin/TV/ /mnt/tank/media/TV/ | wc -l); [ "$n" -eq 0 ] && echo OK || echo "UNTERSCHIEDE ($n)"
sudo rm -rf /mnt/tank/jellyfin/TV
```

### lancache
Nur falls noch vorhanden:
```bash
sudo rm -rf /mnt/tank/jellyfin/lancache
```

**Hinweis:** Die `rm`-Zeile jedes Blocks erst ausführen, wenn die Zeile davor `OK` gemeldet hat.
Bei `UNTERSCHIEDE` einfach die `rsync`-Zeile wiederholen. Meldet `rsync` Fehler zu ACLs,
stammen sie von TrueNAS-ACLs und sind harmlos – die Rechte werden in B6 neu gesetzt.

## B6. Rechte setzen (nach allen Medien-Ordnern)

```bash
sudo chown -R root:media /mnt/tank/media/{Movies,TV,Music,Manga,Books,Comics,Audiobooks}
sudo find /mnt/tank/media/{Movies,TV,Music,Manga,Books,Comics,Audiobooks} -type d -exec chmod 2775 {} +
sudo find /mnt/tank/media/{Movies,TV,Music,Manga,Books,Comics,Audiobooks} -type f -exec chmod 664 {} +
```
`dbglas` gehört bereits UID 1003 = `dbglas`, `lmlzr` wurde im psycho-Block gesetzt.

## B7. Dienste starten

```bash
sudo nixos-rebuild switch --flake .#neotokyo
sudo systemctl start sanoid
systemctl --failed
```
Samba-Passwörter:
```bash
sudo smbpasswd -a lmlzr
sudo smbpasswd -a dbglas
```
Test: `smbclient -L //neotokyo -U lmlzr` (zeigt share, lmlzr, dbglas, media) und
`smbclient -L //neotokyo -U dbglas` (zeigt nur dbglas).

Jellyfin-Bibliotheken auf `/mnt/tank/media/…` stellen, qBittorrent-Speicherort
`/mnt/tank/media/downloads`, Sonarr/Radarr/Lidarr Root-Folder `/mnt/tank/media/TV`, `/Movies`, `/Music`.

## B8. Aufräumen und Abschluss

Nur leere Ordner und TrueNAS-Reste:
```bash
sudo rmdir /mnt/tank/jellyfin
sudo zfs list -r -o name,used tank/iocage
sudo zfs destroy -r tank/iocage
sudo rm -rf /mnt/tank/iocage
ls /mnt/tank
```
Erwartet: nur `lancache  media  services  share`.

```bash
sudo zpool status tank
zfs list -t snapshot | head
sudo zpool scrub tank
```
Erst wenn alles einige Tage läuft, optional `sudo zpool upgrade tank` (danach kein Rückweg zu TrueNAS).
