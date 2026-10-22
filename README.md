# Nixos-Server
Nixos Server config for switching von proxmox to nix

## Dienste und Ports

Erreichbar unter `http://neotokyo:<port>` bzw. `http://10.0.0.5:<port>`.
**Erreichbar:** *LAN* = aus dem Heimnetz, *lokal* = nur auf dem Server selbst.
Öffentlicher Zugang über den VPS ist noch nicht eingerichtet.

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
| qBittorrent | http://neotokyo:8080 | LAN | läuft im VPN-Namespace; vom Server selbst: `192.168.15.1:8080` |
| Pterodactyl Panel | http://10.0.0.5:8090 | LAN | über die IP öffnen (`APP_URL`) |

### Sonstige Ports

| Dienst | Port | Erreichbar | Hinweis |
|---|---|---|---|
| SSH | 22/tcp | LAN | |
| Lancache | 80/tcp, 443/tcp | LAN | nur auf `10.0.0.5`; Clients brauchen DNS-Umleitung der Spiele-Domains |
| Samba | 139/tcp, 445/tcp, 137–138/udp | LAN | nur auf der LAN-Schnittstelle und nur aus privaten Netzen, siehe „Speicher (NAS)“ |
| Windows-Netzwerkerkennung (wsdd) | 5357/tcp, 3702/udp | LAN | Server erscheint unter „Netzwerk“ |
| Jellyfin (Discovery) | 1900/udp, 7359/udp | LAN | Clients finden den Server im LAN |
| Pterodactyl Wings API | 8443/tcp | LAN | Browser-Konsole und Panel sprechen Wings hierüber an |
| Pterodactyl SFTP | 2022/tcp | LAN | Dateizugriff auf Gameserver, Login mit Panel-Benutzer |
| Gameserver | 25565–25600/tcp+udp | LAN | im Panel als Allocations anlegen |
| MariaDB | Socket | lokal | nur Unix-Socket, für das Panel |
| Redis (Pterodactyl) | Socket | lokal | nur Unix-Socket |
| Lancache Metrics | 8080/tcp | lokal | nginx auf `localhost`; aus dem LAN geht 8080 an qBittorrent |

Laufen inzwischen auf einem anderen Host (hier auskommentiert): Home Assistant, Karakeep,
Mealie, Syncthing, Mosquitto, Portainer, Firefox.

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
Umzug von TrueNAS, Plattentausch, Snapshots, L2ARC: **[docs/NAS-Migration.md](docs/NAS-Migration.md)**.

| Dataset | Pfad | Inhalt | Snapshots |
|---|---|---|---|
| `tank/media` | `/mnt/tank/media` | Filme, Serien, Musik …, `downloads/` | 7 Tage |
| `tank/share` | `/mnt/tank/share` | `lmlzr/`, `dbglas/` | 24 h, 30 Tage, 6 Monate |
| `tank/services` | `/mnt/tank/services` | Daten der Dienste (s. u.) | 14 Tage, 3 Monate |
| `tank/lancache` | `/mnt/tank/lancache` | Spiele-Cache, max. 2 TB | keine |

Dienst-Daten liegen auf dem Pool und werden per Bind-Mount eingehängt (`modules/links.nix`):
`/var/lib/<dienst>` ← `/mnt/tank/services/<dienst>` für Jellyfin, Audiobookshelf, Stirling-PDF,
Sonarr, Radarr, Lidarr, Prowlarr, qBittorrent, MariaDB (`mysql`), Pterodactyl (`pterodactyl-panel`,
`pterodactyl-wings`). Fehlt der Pool, bootet das System trotzdem, diese Dienste starten dann aber nicht.

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

## Secrets

Liegen nicht im Repo, sondern auf dem Server unter `/etc/secrets/` (Dateien `0600`):

| Datei | Besitzer | Inhalt | Genutzt von |
|---|---|---|---|
| `proton-wg.conf` | root | WireGuard-Config von ProtonVPN | qBittorrent-VPN-Namespace |

Fehlt eine Datei, startet der jeweilige Dienst nicht.

## Einmalige Einrichtung

- Samba-Passwörter: `sudo smbpasswd -a lmlzr` und `sudo smbpasswd -a dbglas`
- SteamPrefill: `cd /var/lib/steam-prefill && SteamPrefill select-apps`
- *arr: qBittorrent als Download-Client unter `192.168.15.1:8080` eintragen, Medien unter `/mnt/tank/media`, Downloads unter `/mnt/tank/media/downloads`
