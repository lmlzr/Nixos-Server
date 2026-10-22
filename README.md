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
| Samba | 139/tcp, 445/tcp, 137–138/udp | LAN | Freigabe `share` → `/mnt/TB1` |
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

## Secrets

Liegen nicht im Repo, sondern auf dem Server unter `/etc/secrets/` (Dateien `0600`):

| Datei | Besitzer | Inhalt | Genutzt von |
|---|---|---|---|
| `proton-wg.conf` | root | WireGuard-Config von ProtonVPN | qBittorrent-VPN-Namespace |

Fehlt eine Datei, startet der jeweilige Dienst nicht.

## Einmalige Einrichtung

- Samba-Passwort: `sudo smbpasswd -a lmlzr`
- SteamPrefill: `cd /var/lib/steam-prefill && SteamPrefill select-apps`
- *arr: qBittorrent als Download-Client unter `192.168.15.1:8080` eintragen, Medien unter `/mnt/TB1/media`
