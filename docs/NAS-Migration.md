# NAS: Umzug von TrueNAS (Pool `TB1`) nach NixOS (Pool `tank`)

Dieser Ablauf wurde im VM-Test `tests/nas-migration.nix` mit einem nachgebauten
TrueNAS-Mirror durchgespielt (`nix build .#checks.x86_64-linux.nas-migration -L`).
Am echten Pool läuft nichts automatisch – jeden Befehl selbst ausführen und die Ausgabe prüfen.

> **Zum Abarbeiten: [UMZUG.md](UMZUG.md)** – alle Befehle vor und nach dem Umzug, ein Block pro
> Ordner, Reihenfolge frei, Ordner können vorab unter TrueNAS kopiert werden. Diese Datei hier
> erklärt Hintergründe, Rückweg und Wartung; Phasen C–F unten sind die ursprüngliche Variante
> ohne Vorab-Kopie.

## Ausgangslage (Bestandsaufnahme 22.10.2026)

| | |
|---|---|
| Pool | `TB1`, **Mirror** aus 2× 16 TB, `ashift=12`, ONLINE, letzter Scrub ohne Fehler |
| Platten | `/dev/disk/by-id/wwn-0x5000c500e7ab0441`, `/dev/disk/by-id/wwn-0x5000c500e7aafd88` |
| Belegung | 7,74 TB von 14,5 TB (53 %), 6,81 TB frei – vor dem Löschen des Lancache-Ordners; jetzt ca. 6,4 TB belegt, ca. 8,1 TB frei (`zpool list TB1`) |
| Herkunft | TrueNAS CORE, ZFS 2.1.14 (NixOS hat 2.4.4 → Import problemlos) |
| Eigenschaften | `compression=lz4`, `atime=off`, `recordsize=128K`, `acltype=nfsv4` |
| Daten | alles im Root-Dataset `TB1`, keine Snapshots |

| Ordner | Größe | Besitzer | Ziel |
|---|---|---|---|
| `jellyfin/TV` | 3,3 TB | 1001 | `tank/media` → `/mnt/tank/media/TV` |
| `jellyfin/Movies` | 1,9 TB | 1001 | `/mnt/tank/media/Movies` |
| `jellyfin/lancache` | 1,3 TB | 1001 | **bereits gelöscht** |
| `jellyfin/Audiobooks`, `Manga`, `Music`, `Books`, `Comics` | ~212 GB | 1001 | `/mnt/tank/media/…` (zusätzlich extern gesichert) |
| `psycho` | 892 GB | 1000 | `tank/share` → `/mnt/tank/share/lmlzr` |
| `server` | 75 GB | 1002 | `tank/services` → `/mnt/tank/services/alt-truenas` |
| `dbglas` | 46 GB | 1003 | `/mnt/tank/share/dbglas` |
| `iocage` | 8 MB | root | TrueNAS-Reste, am Ende löschen |

UIDs: `lmlzr` = 1000, `dbglas` = 1003 wie unter TrueNAS → deren Dateien passen ohne `chown`.

## Zielstruktur

| Dataset | Mountpoint | Eigenschaften | Snapshots |
|---|---|---|---|
| `tank` | `/mnt/tank` | Root, nach dem Umzug leer | keine |
| `tank/media` | `/mnt/tank/media` | `recordsize=1M` | 7 tägliche |
| `tank/share` | `/mnt/tank/share` | `normalization=formD` | 30 tägl., 6 monatl. |
| `tank/services` | `/mnt/tank/services` | Standard | 14 tägl., 3 monatl. |
| `tank/lancache` | `/mnt/tank/lancache` | `recordsize=1M`, `quota=2T` | keine |
| `tank/reserved` | – | `refreservation=500G` | – |

Alle mit `mountpoint=legacy`; eingehängt werden sie von NixOS (`Hardware/storage.nix`).
Downloads liegen in `/mnt/tank/media/downloads` – im selben Dataset wie die Medien,
damit Sonarr/Radarr Hardlinks und schnelle Verschiebungen nutzen können.

---

## Phase A – Vorbereitung (Proxmox und TrueNAS laufen noch)

1. **Unersetzliches zusätzlich extern sichern** – mindestens `psycho`, `dbglas`, `server`
   (zusammen ~1 TB). Der Umzug ist risikoarm, aber ein Mirror ist kein Backup.
2. In TrueNAS **alle Aufgaben abschalten**: Periodic Snapshot Tasks, Replication, Scrub Tasks,
   Cloud Sync, Rsync Tasks.
3. Zustand festhalten (in der TrueNAS-Shell), **kein Scrub** – der kommt nach dem Umbau (Phase F):
   ```bash
   zpool status -v TB1
   ```
   Erwartet: `state: ONLINE`, `errors: No known data errors`.
4. Dienste mit Daten auf `TB1` stoppen, TrueNAS-VM **herunterfahren**.
   **Nicht** „Export/Disconnect“ im TrueNAS-Menü verwenden (dort ist „Destroy data“ eine Option).
5. Proxmox-Host herunterfahren.

## Phase B – NixOS installieren

1. **Beide 16-TB-Platten abstecken** (Strom oder SATA). So kann der Installer sie nicht anfassen.
2. NixOS auf die Systemplatte installieren, dieses Repo klonen.
3. Die vom Installer erzeugte `hardware-configuration.nix` ins Repo übernehmen.
4. Netzwerkschnittstelle prüfen: `ip link`. Heißt sie nicht `enp3s0`, in `configuration.nix`
   `nas.lanInterface = "<name>";` setzen und in `services/lancache.nix` anpassen.
5. Ersten Rebuild machen (der Pool fehlt noch – das ist in Ordnung, das System bootet trotzdem
   und die Dienste mit Pool-Daten bleiben aus):
   ```bash
   sudo nixos-rebuild switch --flake .#neotokyo
   ```
6. Herunterfahren, **Platten wieder anschließen**, starten.

## Phase C – Pool übernehmen

1. Pool sichtbar?
   ```bash
   sudo zpool import
   ```
   Erwartet: `pool: TB1`, `state: ONLINE`, `mirror-0` mit zwei `wwn-0x5000c500…`-Geräten.
2. Importieren und dabei umbenennen. `-f` ist nötig, weil der Pool zuletzt unter TrueNAS lief;
   `-N` hängt noch nichts ein:
   ```bash
   sudo zpool import -f -N TB1 tank
   sudo zpool status tank
   ```
3. **Kein `zpool upgrade`!** Solange das nicht passiert, kann TrueNAS den Pool wieder lesen
   (Rückweg). Die Meldung „Some supported features are not enabled“ ignorieren.
4. Eigenschaften für Linux/Samba setzen (alle umkehrbar):
   ```bash
   sudo zfs set mountpoint=legacy atime=off xattr=sa acltype=posixacl tank
   ```
5. Datasets anlegen:
   ```bash
   sudo zfs create -o mountpoint=legacy -o recordsize=1M tank/media
   sudo zfs create -o mountpoint=legacy -o utf8only=on -o normalization=formD tank/share
   sudo zfs create -o mountpoint=legacy tank/services
   sudo zfs create -o mountpoint=legacy -o recordsize=1M -o quota=2T tank/lancache
   sudo zfs create -o mountpoint=none -o refreservation=500G tank/reserved
   ```
6. Neu starten. Danach prüfen:
   ```bash
   findmnt -t zfs
   systemctl --failed
   ```
   Erwartet: `/mnt/tank`, `/mnt/tank/media`, `/share`, `/services`, `/lancache` sind eingehängt,
   keine fehlgeschlagenen Units. Die alten Ordner liegen jetzt unter `/mnt/tank/` (`jellyfin`,
   `psycho`, …).

## Phase D – Daten umziehen

Zwischen Datasets ist `mv` immer Kopieren + Löschen. Deshalb Ordner für Ordner:
kopieren → prüfen → erst dann die Quelle löschen. Gesamtdauer grob 12–15 Stunden,
am besten in `tmux` arbeiten (`nix-shell -p tmux`), damit eine getrennte SSH-Verbindung nichts abbricht.

Während des Umzugs Dienste stoppen, die schreiben könnten:
```bash
sudo systemctl stop jellyfin sonarr radarr lidarr qbittorrent samba-smbd
```

**Hilfsfunktion** (in die Shell einfügen) – kopiert, vergleicht Dateianzahl und Größe und
löscht die Quelle nur, wenn beides übereinstimmt:
```bash
umzug() {
  src="$1"; dst="$2"
  sudo mkdir -p "$dst"
  sudo rsync -aHAX --info=progress2 "$src"/ "$dst"/ || { echo "rsync FEHLER"; return 1; }
  a=$(sudo find "$src" | wc -l); b=$(sudo find "$dst" | wc -l)
  sa=$(sudo du -s --apparent-size -B1 "$src" | cut -f1); sb=$(sudo du -s --apparent-size -B1 "$dst" | cut -f1)
  echo "Einträge: $a -> $b   Bytes: $sa -> $sb"
  if [ "$a" != "$b" ] || sudo rsync -aHAX --dry-run --itemize-changes "$src"/ "$dst"/ | grep -q .; then
    echo "UNTERSCHIEDE – Quelle bleibt erhalten"; return 1
  fi
  read -p "Quelle $src löschen? [j/N] " ok && [ "$ok" = j ] && sudo rm -rf "$src"
}
```
Meldet `rsync` Fehler zu ACLs (`set_acl`, `Operation not supported`), stammen die von den
alten NFSv4-ACLs aus TrueNAS. Die Rechte werden danach ohnehin neu gesetzt: dann in der
Funktion beide Male `-aHAX` durch `-aHX` ersetzen und den Ordner erneut umziehen.

Reihenfolge (die kleinen zuerst, die großen am Ende):

```bash
umzug /mnt/tank/dbglas           /mnt/tank/share/dbglas
umzug /mnt/tank/server           /mnt/tank/services/alt-truenas
umzug /mnt/tank/psycho           /mnt/tank/share/lmlzr
for d in Books Comics Music Manga Audiobooks; do umzug /mnt/tank/jellyfin/$d /mnt/tank/media/$d; done
umzug /mnt/tank/jellyfin/Movies  /mnt/tank/media/Movies
umzug /mnt/tank/jellyfin/TV      /mnt/tank/media/TV
sudo rmdir /mnt/tank/jellyfin
```

Freier Platz zwischendurch: `zfs list -o name,used,avail tank`. Das größte Stück (TV, 3,3 TB)
passt problemlos in den freien Platz (der alte Lancache-Ordner ist bereits gelöscht).

**Rechte setzen** – gezielt, nicht rekursiv mit 777:
```bash
# Medien: Gruppe media darf lesen und schreiben
sudo chown -R root:media /mnt/tank/media/{Movies,TV,Music,Manga,Books,Comics,Audiobooks}
sudo find /mnt/tank/media/{Movies,TV,Music,Manga,Books,Comics,Audiobooks} -type d -exec chmod 2775 {} +
sudo find /mnt/tank/media/{Movies,TV,Music,Manga,Books,Comics,Audiobooks} -type f -exec chmod 664 {} +
# lmlzr: eigene Dateien (UID passt schon, Gruppe vereinheitlichen)
sudo chown -R lmlzr:users /mnt/tank/share/lmlzr
```
`dbglas` gehört bereits UID 1003 = `dbglas`, dort ist nichts zu tun. Die obersten Ordner
(`media`, `share`, `share/lmlzr`, `share/dbglas`, `media/downloads`) setzt `nas-dirs.service`
bei jedem Start selbst.

**Dienste wieder starten** und den ersten Snapshot anstoßen:
```bash
sudo nixos-rebuild switch --flake .#neotokyo
sudo systemctl start sanoid
```
(sanoid merkt sich die Dataset-Liste bis zu 20 Minuten; die ersten Snapshots können so lange dauern.)

`/mnt/tank/services/alt-truenas` enthält die alten Docker-Daten. Pro Dienst in den passenden
Ordner unter `/mnt/tank/services/<dienst>` übernehmen (Zuordnung: README → „Speicher (NAS)“),
Besitzer setzen, Dienst neu starten; danach den Ordner `alt-truenas` löschen.

## Phase E – Samba und Jellyfin

1. Samba-Passwörter setzen:
   ```bash
   sudo smbpasswd -a lmlzr
   sudo smbpasswd -a dbglas
   ```
2. Testen (vom Server aus oder von einem Client im LAN):
   ```bash
   smbclient -L //neotokyo -U lmlzr     # share, lmlzr, dbglas, media
   smbclient -L //neotokyo -U dbglas    # nur dbglas
   ```
   Windows: `\\neotokyo\media` usw. Linux: `smb://neotokyo/media`.
3. Jellyfin: Bibliothekspfade in den Einstellungen auf `/mnt/tank/media/Movies`, `/mnt/tank/media/TV`
   usw. stellen. Achtung: Jellyfin liest dabei neu ein, der „Gesehen“-Status kann verloren gehen.
   Wer die alten Pfade behalten will (z. B. Container-Pfade wie `/data/movies`), kann sie per
   Bind-Mount weiterführen – vorher fragen.
4. qBittorrent: Standard-Speicherort `/mnt/tank/media/downloads`.
   Sonarr/Radarr/Lidarr: Root-Folder `/mnt/tank/media/TV`, `/Movies`, `/Music`.

## Phase F – Aufräumen und Abschlussprüfung

1. TrueNAS-Reste löschen – **nur** nach Prüfung, dass nur leere Jail-Ordner drin sind:
   ```bash
   sudo zfs list -r -o name,used tank/iocage
   sudo zfs destroy -r tank/iocage
   sudo rm -rf /mnt/tank/iocage
   ```
2. Abschlussprüfung:
   ```bash
   sudo zpool status tank                 # ONLINE, keine Fehler
   ls /mnt/tank                           # nur lancache media services share
   zfs list -t snapshot | head            # Snapshots vorhanden
   systemctl --failed                     # leer
   sudo systemctl start zfs-health; journalctl -u zfs-health -n 3
   ```
3. Neustart-Test: neu starten, dann erneut `findmnt -t zfs` und `systemctl --failed`.
4. **Scrub starten** – der erste unter NixOS, über den ganzen Pool inklusive der neu
   geschriebenen Daten (dauert ~12 h, die Platten laufen so lange durch):
   ```bash
   sudo zpool scrub tank
   sudo zpool status tank                 # Fortschritt
   ```
   Erwartet am Ende: `scrub repaired 0B … with 0 errors`, `errors: No known data errors`.
   Werden Fehler repariert oder gemeldet: `zpool status -v tank` zeigt betroffene Dateien,
   dann SMART-Werte beider Platten prüfen (siehe „Überwachung“). Danach übernimmt der monatliche
   `zfs-scrub.timer`.
5. Erst wenn alles einige Tage läuft: optional `sudo zpool upgrade tank`
   (danach kein Rückweg zu TrueNAS mehr).

## Rückweg

Bis Phase D Schritt 1 (Löschen des ersten Quellordners) ist alles umkehrbar:
NixOS herunterfahren, Proxmox/TrueNAS wieder installieren, in TrueNAS den Pool importieren
(`zpool import -f tank TB1` benennt ihn zurück). Voraussetzung: kein `zpool upgrade`.
Gesetzte Eigenschaften (`mountpoint`, `xattr`, `acltype`) zurückstellen:
`zfs inherit mountpoint TB1; zfs set acltype=nfsv4 xattr=on TB1`.

---

# Betrieb und Wartung

## Was bei welchem Ereignis passiert

| Ereignis | Folge |
|---|---|
| Eine HDD fällt aus | kein Datenverlust, Pool läuft `DEGRADED` weiter → Platte tauschen |
| Datei versehentlich gelöscht | aus Snapshot holen (`media` 7 Tage, `share` bis 6 Monate, `services` 3 Monate) |
| Verschlüsselungstrojaner über SMB | Snapshots sind über SMB nicht löschbar → zurückholen |
| Beide HDDs defekt, Brand, Diebstahl | **alles weg, was nicht extern gesichert ist** |
| Lancache voll / weg | egal, wird neu befüllt |
| SSD (L2ARC) defekt | kein Datenverlust, nur Cache weg |
| Systemplatte defekt | NixOS neu installieren, Repo klonen, `zpool import tank` – alle Dienst-Daten liegen auf dem Pool |

Ein externes Backup ist vorbereitet (`modules/backup.nix`, `nas.backup.enable`), aber noch aus.

## Datei aus Snapshot zurückholen

```bash
ls /mnt/tank/share/.zfs/snapshot/
cp -a /mnt/tank/share/.zfs/snapshot/autosnap_<datum>_daily/lmlzr/Datei /mnt/tank/share/lmlzr/
```

## Plattentausch

1. Defekte Platte finden: `sudo zpool status -P tank` (Gerät mit `FAULTED`/`UNAVAIL` oder Fehlerzählern).
   Seriennummer zuordnen: `ls -l /dev/disk/by-id/ | grep <wwn>` und `sudo smartctl -i /dev/disk/by-id/<wwn>`.
2. Platte offline nehmen: `sudo zpool offline tank <gerät>`.
3. Ausschalten, Platte tauschen (gleich groß oder größer), einschalten.
4. Neue Platte finden: `ls -l /dev/disk/by-id/ | grep -v part`.
5. Ersetzen: `sudo zpool replace tank <altes-gerät> /dev/disk/by-id/<neue-platte>`.
6. Resilver verfolgen: `watch zpool status tank` (bei ~8 TB Daten viele Stunden).
   Nach dem Resilver startet automatisch ein Scrub (`ZED_SCRUB_AFTER_RESILVER`).

## Überwachung

- `zfs-health.timer` (täglich): Pool-Zustand und Belegung ≥ 80 % → Fehler im Journal und an alle Terminals.
  `journalctl -p err -u zfs-health`
- `smartd`: Kurztest täglich 02:00, Langtest am 1. des Monats 03:00, Temperaturwarnung ab 45 °C.
  `sudo smartctl -a /dev/disk/by-id/wwn-0x5000c500e7ab0441`
- `zfs-scrub.timer` (monatlich): Ergebnis in `zpool status tank`.
- ZED meldet Plattenfehler und Scrub-Ergebnisse ins Journal: `journalctl -u zfs-zed`.
- Checkmk-Agent auf Port 6556 liefert Pool-Zustand, Datasets und (1× täglich) SMART-Werte
  an den Checkmk-Server – siehe README „Monitoring (Checkmk)“.
- Benachrichtigung per Mail/ntfy: noch offen (kommt mit dem Backup-Konzept).

## Spindown der HDDs

`modules/hdd-spindown.nix` (hd-idle): die beiden 16-TB-Platten werden nach 15 min ohne Zugriff
abgeschaltet; Systemplatte und SSD nie. Einstellbar über `nas.spindown.idleMinutes`.

```bash
sudo hdparm -C /dev/disk/by-id/wwn-0x5000c500e7ab0441   # "standby" = schläft, "active/idle" = läuft
sudo hdparm -C /dev/disk/by-id/wwn-0x5000c500e7aafd88
journalctl -u hd-idle
```

Wann die Platten trotzdem wach bleiben – alles, was auf `tank` liest oder schreibt:
- Dienst-Daten in `tank/services` (Jellyfin-Datenbank, MariaDB, Sonarr/Radarr, Gameserver, Logs)
- die nächtlichen Snapshots (sanoid, einmal pro Nacht für alle Datasets – gewollt)
- laufende Downloads in `tank/media/downloads`, Lancache-Downloads
- Bibliotheks-Scans von Jellyfin und Ordner-Scans von Sonarr/Radarr/Lidarr
- der tägliche SMART-Kurztest (02:00) und der monatliche Scrub – gewollt
- das SMART-Plugin des Checkmk-Agents (1× täglich)

Dauerhaft schlafen können die Platten erst, wenn `services` auf einem eigenen SSD-Pool liegt.
smartd ist so eingestellt (`-n standby`), dass es schlafende Platten nicht weckt.

Zählerstand der Starts (Verschleiß beobachten):
`sudo smartctl -A /dev/disk/by-id/wwn-0x5000c500e7ab0441 | grep -E 'Start_Stop|Load_Cycle'`

## L2ARC (SSD-Lesecache) – nur bei nachgewiesenem Nutzen

Bei 48 GB RAM (ARC max. 20 GiB) und Filmen, die einmal am Stück gelesen werden, bringt L2ARC
meist nichts: ZFS schreibt Streaming-Lesezugriffe standardmäßig gar nicht in den L2ARC.

**Messen** (nach einigen Wochen Normalbetrieb):
```bash
arc_summary | less            # Abschnitt "ARC total accesses": Hit ratio
arcstat 5                      # laufend: hit%, miss%
```
Liegt die ARC-Trefferquote über ~90 % und sind `demand_metadata_misses` niedrig → kein L2ARC.

**Testweise hinzufügen** (SSD-ID vorher mit `ls -l /dev/disk/by-id/` ermitteln):
```bash
sudo zpool add tank cache /dev/disk/by-id/<ssd-id>
sudo zfs set secondarycache=metadata tank/media   # nur Metadaten der Medien cachen
```
**Nutzen messen:**
```bash
zpool iostat -v tank 5                                          # Lesezugriffe auf "cache"
grep -E '^l2_(hits|misses|size|hdr_size) ' /proc/spl/kstat/zfs/arcstats
```
`l2_hdr_size` ist der RAM-Verbrauch für die L2ARC-Verwaltung (bei 500 GB grob 50–400 MB).
SSD-Verschleiß: `sudo smartctl -a /dev/disk/by-id/<ssd-id>` (Percentage Used / Wear Leveling).

**Wieder entfernen** – ohne Datenverlust, danach fehlt nur der Cache:
```bash
sudo zpool remove tank /dev/disk/by-id/<ssd-id>
```

## Fehlerbehebung

| Symptom | Prüfen |
|---|---|
| Dienste starten nicht nach Boot | `zpool status`, `findmnt -t zfs`. Fehlt der Pool: `sudo zpool import tank`, dann `sudo systemctl start local-fs.target` oder neu starten |
| `cannot import: pool was previously in use from another system` | einmalig `sudo zpool import -f tank` (passiert nach Hardware-/hostId-Wechsel) |
| Samba: Zugriff verweigert | `sudo pdbedit -L` (Benutzer vorhanden?), Gruppen: `id lmlzr`, Rechte: `ls -ld /mnt/tank/media` |
| Samba: Client außerhalb privater Netze | `hosts allow` in `services/smb.nix` erlaubt nur private Adressbereiche |
| Pool fast voll | `zfs list -o name,used,avail,refer -t all`; alte Snapshots: `zfs list -t snapshot -o name,used -s used`; Notreserve: `zfs set refreservation=none tank/reserved` |
