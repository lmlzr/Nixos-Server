# Nixos-Server
Nixos Server config for switching von proxmox to nix

## Dienste und Ports

Erreichbar unter `http://neotokyo:<port>` bzw. `http://10.0.0.5:<port>`.

### Weboberflächen

| Dienst | Adresse | Hinweis |
|---|---|---|
| Jellyfin | http://neotokyo:8096 | HTTPS: 8920 (nur mit eigenem Zertifikat) |
| Home Assistant | http://neotokyo:8123 | |
| Audiobookshelf | http://neotokyo:13378 | |
| Karakeep | http://10.0.0.5:3000 | über die IP öffnen, sonst klappt der Login nicht (`NEXTAUTH_URL`) |
| Mealie | http://10.0.0.5:9925 | über die IP öffnen (`BASE_URL`) |
| Stirling-PDF | http://neotokyo:8083 | |
| Syncthing | http://neotokyo:8384 | Login: `lmlzr` + `/etc/secrets/syncthing-gui` |
| Sonarr | http://neotokyo:8989 | |
| Radarr | http://neotokyo:7878 | |
| Lidarr | http://neotokyo:8686 | |
| Prowlarr | http://neotokyo:9696 | |
| qBittorrent | http://neotokyo:8080 | läuft im VPN-Namespace; vom Server selbst: `192.168.15.1:8080` |
| Portainer | https://neotokyo:9443 | Docker |
| Firefox | https://neotokyo:4045 | Docker; Port 4044 ist unverschlüsseltes HTTP |

### Sonstige Ports

| Dienst | Port | Hinweis |
|---|---|---|
| SSH | 22/tcp | |
| Lancache | 80/tcp, 443/tcp | nur auf `10.0.0.5`; Clients brauchen DNS-Umleitung der Spiele-Domains |
| Samba | 139/tcp, 445/tcp, 137–138/udp | Freigabe `share` → `/mnt/TB1` |
| Syncthing (Sync) | 22000/tcp+udp, 21027/udp | Datenübertragung und Geräteerkennung |
| Jellyfin (Discovery) | 1900/udp, 7359/udp | Clients finden den Server im LAN |
| Portainer Edge | 8000/tcp | nur für Edge-Agents nötig |
| Mosquitto (MQTT) | 1883/tcp | nur `127.0.0.1`, nicht im LAN erreichbar |

Docker-Container (Portainer, Firefox) veröffentlichen ihre Ports an der NixOS-Firewall vorbei –
sie sind auch ohne Eintrag in `networking.firewall` im LAN erreichbar.

## Secrets

Liegen nicht im Repo, sondern auf dem Server unter `/etc/secrets/` (Dateien `0600`):

| Datei | Besitzer | Inhalt | Genutzt von |
|---|---|---|---|
| `proton-wg.conf` | root | WireGuard-Config von ProtonVPN | qBittorrent-VPN-Namespace |
| `syncthing-gui` | lmlzr | GUI-Passwort (Klartext, ohne Zeilenumbruch) | Syncthing |
| `firefox.env` | root | `CUSTOM_USER=...` und `PASSWORD=...` | Firefox-Container |

Fehlt eine Datei, startet der jeweilige Dienst nicht.

## Einmalige Einrichtung

- Samba-Passwort: `sudo smbpasswd -a lmlzr`
- SteamPrefill: `cd /var/lib/steam-prefill && SteamPrefill select-apps`
- *arr: qBittorrent als Download-Client unter `192.168.15.1:8080` eintragen, Medien unter `/mnt/TB1/media`
