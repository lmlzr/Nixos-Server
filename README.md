# Nixos-Server
Nixos Server config for switching von proxmox to nix

## Dienste und Ports

Erreichbar unter `http://neotokyo:<port>` bzw. `http://10.0.0.5:<port>`.
**Erreichbar:** *LAN* = aus dem Heimnetz, *lokal* = nur auf dem Server selbst.
Öffentlich ist nur Jellyfin unter https://jellyfin.lmlzr.com (nginx auf dem VPS, per WireGuard
`10.10.0.1` → `10.0.0.5:8096`; `10.10.0.1` steht in Jellyfin als bekannter Proxy).

### Weboberflächen

| Dienst | Adresse | Erreichbar | Hinweis |
|---|---|---|---|
| Jellyfin | http://neotokyo:8096 | LAN | HTTPS: 8920 (nur mit eigenem Zertifikat) |
| Audiobookshelf | http://neotokyo:13378 | LAN | |
| Stirling-PDF | http://neotokyo:8083 | LAN | |
| Sonarr | http://neotokyo:8989 | LAN | |
| Radarr | http://neotokyo:7878 | LAN | |
| Lidarr | http://neotokyo:8686 | LAN | |
| Prowlarr | http://neotokyo:9696 | LAN | |
| Seerr | http://neotokyo:5055 | LAN | Film-/Serienwünsche (früher Jellyseerr); Einrichtung siehe unten |
| qBittorrent | http://neotokyo:8080 | LAN | läuft im VPN-Namespace; vom Server selbst: `192.168.15.1:8080` |
| Pterodactyl Panel | http://10.0.0.5:8090 | LAN | über die IP öffnen (`APP_URL`) |
| Portainer | https://neotokyo:9443 | LAN | Docker-Verwaltung; Port 8000 nur für Edge-Agents |
| Lancache-Dashboard | http://neotokyo:3000 | LAN | Downloads, HIT/MISS, Clients, gecachte Spiele; siehe „Lancache“ |

### Sonstige Ports

| Dienst | Port | Erreichbar | Hinweis |
|---|---|---|---|
| SSH | 22/tcp | LAN | |
| Lancache | 80/tcp, 443/tcp | LAN | nur auf `10.0.0.5`; Clients brauchen DNS-Umleitung der Spiele-Domains |
| Samba | 139/tcp, 445/tcp, 137–138/udp | LAN | nur auf der LAN-Schnittstelle und nur aus privaten Netzen, siehe „Speicher (NAS)“ |
| Windows-Netzwerkerkennung (wsdd) | 5357/tcp, 3702/udp | LAN | Server erscheint unter „Netzwerk“ |
| Checkmk-Agent | 6556/tcp | LAN | nur LAN-Schnittstelle, nur vom Checkmk-Server `10.0.0.3` |
| Jellyfin (Discovery) | 1900/udp, 7359/udp | LAN | Clients finden den Server im LAN |
| Pterodactyl Wings API | 8443/tcp | LAN | Browser-Konsole und Panel sprechen Wings hierüber an |
| Pterodactyl SFTP | 2022/tcp | LAN | Dateizugriff auf Gameserver, Login mit Panel-Benutzer |
| Gameserver | 25565–25600/tcp+udp | LAN | im Panel als Allocations anlegen |
| MariaDB | Socket | lokal | nur Unix-Socket, für das Panel |
| Redis (Pterodactyl) | Socket | lokal | nur Unix-Socket |
| Lancache Metrics | 8080/tcp | lokal | nginx auf `localhost`; aus dem LAN geht 8080 an qBittorrent |
| FlareSolverr | 8191/tcp | lokal | Cloudflare-Umgehung für Prowlarr (`services/arr-stack/flaresolverr.nix`) |

Laufen inzwischen auf einem anderen Host (hier auskommentiert): Home Assistant, Karakeep,
Mealie, Syncthing, Mosquitto, Firefox.

## Jellyfin (aus Docker-Backup)

Datenbank und Einstellungen stammen aus einem Backup des früheren Docker-Jellyfin und enthalten
dessen Pfade. Damit Bibliotheken, Gesehen-Status und Bilder erhalten bleiben, bildet
`services/jellyfin.nix` die alten Pfade nach, statt die Datenbank umzuschreiben:

- `dataDir = "/config/data"`: Bind-Mount von `/mnt/tank/services/jellyfin` (dieselben Daten wie
  `/var/lib/jellyfin`). Muss ein echter Mount sein, kein Symlink: Jellyfin vergleicht die
  Bibliothekspfade als Text, sonst „Die Bibliothek ist in einem ungültigen Zustand“.
- Symlinks: `/config/cache` → `/var/cache/jellyfin`, `/data/movies` → `/mnt/tank/media/Movies`,
  `/data/tvshows` → `TV`, `/data/Books` → `Books`, `/data/music` → `Music`.

Backup einspielen (Dienst vorher stoppen, Datei muss für `jellyfin` lesbar sein):
`sudo -u jellyfin jellyfin --datadir /config/data --configdir /config/data/config --cachedir /var/cache/jellyfin --logdir /config/data/log --restore-archive <backup.zip>`

## Lancache

`services/lancache.nix` (nginx auf `10.0.0.5:80/443`, Cache in `tank/lancache`),
`services/steam-lancache-prefill.nix` (SteamPrefill täglich ab 04:00, nur Updates nach dem ersten Lauf).

- **DNS (Pi-hole auf `10.0.0.3`):** die Spiele-Domains stehen dort in `misc.dnsmasq_lines` als
  `address=/<domain>/10.0.0.5`. Zu jeder Zeile gehört zusätzlich `local=/<domain>/`, sonst gibt
  Pi-hole für IPv6 (AAAA) die echten CDN-Adressen zurück und Steam umgeht den Cache.
  Prüfen: `dig +short AAAA lancache.steamcontent.com @10.0.0.3` muss leer sein.
- Steam erkennt den Cache nur beim Start; im Steam-Log `content_log.txt` steht dann
  `Enabling local content cache at …10.0.0.5`.
- **Dashboard** (`containers/lancache-dashboard.nix`, [imahmud1/lancache-dashboard](https://github.com/imahmud1/lancache-dashboard)):
  liest `/var/log/nginx/lancache/access.log` (Container mit Gruppe `nginx`), Datenbank unter
  `/mnt/tank/services/lancache-dashboard`. Prefill-Traffic (`10.0.0.5`) ist aus der Client-Statistik ausgeblendet.

## Pterodactyl

Panel v1.15.2 und Wings v1.13.4, als eigenes Modul in `services/pterodactyl/`
(an- und abschalten in `configuration.nix` unter `services.pterodactyl`).
Daten liegen auf ZFS: Panel unter `pterodactyl-panel/`, Gameserver unter `pterodactyl-wings/`.

Einrichtung nach dem ersten Rebuild:

1. Admin anlegen: `sudo pterodactyl-artisan p:user:make`
2. **`/var/lib/pterodactyl-panel/secrets/app-key` sichern** (außerhalb des Servers).
   Ohne diesen Schlüssel sind API-Keys, Node-Tokens und 2FA nicht mehr lesbar.
3. Im Panel unter *Admin → Locations* einen Standort anlegen, dann unter *Admin → Nodes* eine Node:
   - FQDN: `10.0.0.5`, *Communicate Over SSL*: **HTTP**, *Behind Proxy*: nein
   - Daemon Port: **8443**, Daemon SFTP Port: **2022**
4. Bei der Node unter *Configuration* den Inhalt nach `/etc/pterodactyl/config.yml` kopieren
   (`sudo nano /etc/pterodactyl/config.yml`), dann `sudo systemctl restart wings`.
   Vorher startet Wings absichtlich nicht.
5. Unter *Allocation* die IP `10.0.0.5` mit den Ports `25565-25600` anlegen.

Ohne SMTP landen Panel-Mails (z. B. Passwort-Reset) nur im Log
(`/var/lib/pterodactyl-panel/storage/logs`). SMTP lässt sich über
`services.pterodactyl.panel.settings` einstellen.

## Speicher (NAS)

ZFS-Pool `tank`: Mirror aus 2× 16 TB (`wwn-0x5000c500e7ab0441`, `wwn-0x5000c500e7aafd88`).
Konfiguration in `Hardware/storage.nix`, Pfade zentral in `modules/storage-paths.nix`.
Befehle für den Umzug von TrueNAS (vorher/nachher, pro Ordner): **[docs/UMZUG.md](docs/UMZUG.md)**.
Hintergründe, Plattentausch, Snapshots, L2ARC: **[docs/NAS-Migration.md](docs/NAS-Migration.md)**.

| Dataset | Pfad | Inhalt | Snapshots |
|---|---|---|---|
| `tank/media` | `/mnt/tank/media` | Filme, Serien, Musik …, `downloads/` | 7 Tage |
| `tank/share` | `/mnt/tank/share` | `lmlzr/`, `dbglas/` | 30 Tage, 6 Monate |
| `tank/lancache` | `/mnt/tank/lancache` | Spiele-Cache, max. 2 TB | keine |
| `tank/backup/services` | – (nicht eingehängt) | nächtliche Kopie von `fast/services` (syncoid, 03:30) | 30 Tage, 6 Monate |
| `fast/services` | `/mnt/fast/services` | Daten der Dienste (s. u.), auf der NVMe | 24 Stunden, 14 Tage, 3 Monate |

Pool `fast`: einzelne NVMe (WD Blue SN580 1 TB) nur für die Dienst-Daten, damit die HDDs
schlafen können. Kein Mirror, deshalb die nächtliche Kopie auf `tank`.
Einrichtung und Wiederherstellung: **[docs/SSD-SERVICES.md](docs/SSD-SERVICES.md)**.

Lese-Cache (L2ARC) von `tank`: Intenso SATA-SSD 256 GB, nur Metadaten (`secondarycache=metadata`),
übersteht Neustarts. Ohne ihn liest der nginx-Cache-Loader des Lancache nach jedem nginx-Start
~15 min lang die Datei-Infos aller Cache-Dateien von den HDDs. Fällt die SSD aus, läuft `tank`
ohne Cache weiter. Entfernen: `sudo zpool remove tank ata-INTENSO_5680079419EE00164834`.

Spindown: die beiden HDDs schalten nach 15 min Leerlauf ab (`modules/hdd-spindown.nix`, hd-idle);
Zustand: `sudo hdparm -C /dev/disk/by-id/wwn-0x5000c500e7ab0441`.

Dienst-Daten liegen auf dem Pool und werden per Bind-Mount eingehängt (`modules/links.nix`):
`/var/lib/<dienst>` ← `/mnt/fast/services/<dienst>` für Jellyfin, Audiobookshelf, Stirling-PDF,
Sonarr, Radarr, Lidarr, Prowlarr, Seerr, qBittorrent, MariaDB (`mysql`), Portainer, Pterodactyl
(`pterodactyl-panel`, `pterodactyl-wings`). Docker-Images selbst liegen in `/var/lib/docker` auf der Systemplatte. Fehlt der Pool, bootet das System trotzdem, diese Dienste starten dann aber nicht.

**Samba-Freigaben** (`services/smb.nix`, nur SMB2+, keine Gäste, nur private Netze):

| Freigabe | Pfad | `lmlzr` | `dbglas` |
|---|---|---|---|
| `share` | `/mnt/tank/share` | lesen/schreiben | unsichtbar |
| `lmlzr` | `/mnt/tank/share/lmlzr` | lesen/schreiben | unsichtbar |
| `dbglas` | `/mnt/tank/share/dbglas` | lesen/schreiben (Admin) | lesen/schreiben |
| `media` | `/mnt/tank/media` | lesen/schreiben (Gruppe `media`) | unsichtbar |

**Tests** (VM, dauern einige Minuten):
```bash
nix build .#checks.x86_64-linux.nas-migration -L
nix build .#checks.x86_64-linux.pterodactyl -L
```

**Test-VM ohne Pool:** in `configuration.nix` die vier NAS-Zeilen (`Hardware/storage.nix` …
`modules/backup.nix`) auskommentieren. Die Pfade unter `/mnt/tank` sind dann normale Ordner.

## Monitoring (Checkmk)

`services/checkmk-agent/`: offizieller Linux-Agent 2.5.0p7 (Bash-Skript von Checkmk, gleiche Version wie der Server) im
klassischen Pull-Modus auf TCP 6556, unverschlüsselt im LAN. In nixpkgs gibt es dafür kein Paket.

- Zugriff nur vom Checkmk-Server `10.0.0.3` (und lokal), eingestellt in `configuration.nix`
  (`services.checkmk-agent.allowedFrom`). Zusätzlich ist der Port nur auf der LAN-Schnittstelle offen.
- Im Checkmk-Server den Host mit „Checkmk agent / API integrations“ anlegen. Ist dort die Regel
  „Enforce agent data encryption“ aktiv, muss sie für diesen Host aus sein (kein TLS-Controller).
- Test vom Server aus: `nc localhost 6556 | head`
- Liefert u. a. CPU, RAM, Dateisysteme, Netzwerk, systemd-Units, ZFS-Pool und -Datasets.
- SMART-Werte: das Plugin weckt schlafende HDDs, deshalb läuft es nur 1× täglich
  (`services.checkmk-agent.smart.interval`). Die Werte in Checkmk sind daher bis zu 24 h alt.
- Version des Agents möglichst gleich oder älter als die des Checkmk-Servers
  (`services/checkmk-agent/package.nix`).

## Secrets

Liegen nicht im Repo, sondern auf dem Server unter `/etc/secrets/` (Dateien `0600`):

| Datei | Besitzer | Inhalt | Genutzt von |
|---|---|---|---|
| `proton-wg.conf` | root | WireGuard-Config von ProtonVPN | qBittorrent-VPN-Namespace |

Fehlt eine Datei, startet der jeweilige Dienst nicht.

## Einmalige Einrichtung

- Samba-Passwörter: `sudo smbpasswd -a lmlzr` und `sudo smbpasswd -a dbglas`
- SteamPrefill: `cd /var/lib/steam-prefill && SteamPrefill select-apps`
- Seerr (http://neotokyo:5055): beim ersten Aufruf „Jellyfin“ wählen, Server `http://localhost:8096`,
  mit dem Jellyfin-Admin anmelden. Danach unter *Settings → Services* Radarr (`http://localhost:7878`)
  und Sonarr (`http://localhost:8989`) mit deren API-Key (*Settings → General* in Radarr/Sonarr) eintragen.
- *arr: qBittorrent als Download-Client unter `192.168.15.1:8080` eintragen, Medien unter `/mnt/tank/media`, Downloads unter `/mnt/tank/media/downloads`
  (nicht `neotokyo:8080`: die Portweiterleitung in den VPN-Namespace greift nur für Zugriffe aus dem LAN)
- qBittorrent: ohne eigenes Passwort erzeugt es bei jedem Start ein temporäres
  (`journalctl -u qbittorrent | grep -i "temporäres Passwort"`, Benutzer `admin`).
  Unter *Optionen → WebUI* ein festes setzen und in Sonarr/Radarr/Lidarr eintragen.
- FlareSolverr in Prowlarr: *Settings → Indexers → + → FlareSolverr*, Host `http://127.0.0.1:8191/`,
  Tag vergeben und denselben Tag bei Indexern hinter Cloudflare setzen.
- Schreibrechte der Medienordner für die Gruppe `media` (inkl. Vererbung auf neue Dateien):
  ```bash
  sudo bash -c 'for D in /mnt/tank/media/{Movies,TV,Music,Books,Audiobooks,Comics,Manga,downloads}; do
    chown -R root:media "$D"; chmod -R g+rwX "$D"; find "$D" -type d -exec chmod g+s {} +
    setfacl -R -m g:media:rwX "$D"; setfacl -R -d -m g:media:rwX "$D"; done'
  ```
