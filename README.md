# Nixos-Server
Nixos Server config for switching von proxmox to nix

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
