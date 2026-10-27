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
| iVentoy | http://10.0.0.5:26000 | LAN | Netzwerk-Boot von ISOs, ohne Anmeldung; siehe „Netzwerk-Boot (iVentoy)“ |
| HandBrake | http://neotokyo:5800 | LAN | Video umwandeln mit NVENC; siehe „HandBrake und MakeMKV“ |
| MakeMKV | http://neotokyo:5801 | LAN | Discs/ISOs nach MKV |

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
| iVentoy PXE | 69/udp (TFTP), 16000/tcp (HTTP), 10809/tcp (NBD) | LAN | nur LAN-Schnittstelle; 67/udp (DHCP) bewusst zu |

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

### Streaming von außen

Über `jellyfin.lmlzr.com` ist der Heim-Upload die Grenze (~38 Mbit/s nach dem Shaper).

- Jellyfin: *Dashboard → Wiedergabe → Streaming* → Internet-Bitrate **10 Mbit/s** (1080p H.264).
- OPNsense: *Firewall → Shaper* → Pipe 40 Mbit/s **FQ-CoDel** auf WAN out, gegen Bufferbloat
  (vorher ~190 ms Ping unter Upload-Last, danach ~34 ms; ohne ihn ruckeln Streams trotz genug Bandbreite).
- Puffert es trotzdem: Engpass ist meist der Mobilfunk am Gerät → in der Jellyfin-App die Bitrate für
  Mobilfunk auf 4–6 Mbit/s setzen. Prüfen: In `/Sessions` liegt der Transcode weit vor der Wiedergabeposition.

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

## Netzwerk-Boot (iVentoy)

`services/iventoy.nix`: [iVentoy](https://www.iventoy.com) (Free Edition) bootet Rechner im LAN
per PXE direkt aus ISO-Dateien, BIOS und UEFI, Linux und Windows. Ohne USB-Stick.

**Wohin mit den ISOs:** `/mnt/tank/media/ISOs`
- vom PC: SMB-Freigabe `media` → Ordner `ISOs`
- per Torrent: in qBittorrent die Kategorie **ISOs** wählen (Speicherort ist dieser Ordner)
- per Prowlarr (http://neotokyo:9696 → *Search*): Kategorie **PC** wählen, suchen, Download-Symbol.
  Prowlarr ordnet PC (4000) und PC/ISO (4020) im Download-Client der qBittorrent-Kategorie
  `ISOs` zu (*Settings → Download Clients → qBittorrent → Mapped Categories*); Filme und Serien
  von Sonarr/Radarr sind davon nicht betroffen
- iVentoy liest den Ordner beim Start; neue ISOs: in der Weboberfläche unter *Image Management* aktualisieren

**Einmalig in iVentoy** (http://10.0.0.5:26000):
1. *Configuration* → **DHCP Server Mode: `External`** (DHCP macht weiter der Router).
2. *Boot Information* → **Server IP: `10.0.0.5`** (nicht die Docker-/VPN-Adressen des Servers).
3. Grünen Start-Knopf drücken. Ab dann startet der Dienst nach jedem Neustart automatisch
   (`IVENTOY_AUTO_RUN`, greift erst, wenn `data/config.dat` gespeichert ist).

Nie `Internal` wählen: dann wäre iVentoy ein zweiter DHCP-Server im LAN. Damit das selbst aus
Versehen nichts anrichtet, ist UDP 67 in der Firewall zu.

**Im Router (OPNsense `10.0.0.1`), DHCP für das LAN → Netzwerk-Boot:**

| Einstellung | Wert |
|---|---|
| Next-Server (Option 66) | `10.0.0.5` |
| Bootdatei (Option 67), automatisch | `iventoy_loader_16000` |
| falls getrennt einstellbar: BIOS | `iventoy_loader_16000_bios` |
| falls getrennt einstellbar: UEFI 64 bit | `iventoy_loader_16000_uefi` |

Die genauen Namen zeigt iVentoy im Modus `External` selbst an; die Tabelle gilt für den
Standard-HTTP-Port 16000. Mit dnsmasq als DHCP: `dhcp-boot=iventoy_loader_16000,,10.0.0.5`.

**Booten:** Am Zielrechner im BIOS/UEFI **Netzwerk-Boot (PXE, „Network Stack“ aktivieren)** wählen,
bei UEFI ggf. Secure Boot aus. Es erscheint das iVentoy-Menü mit allen ISOs.

Daten: `/var/lib/iventoy` (Konfiguration `data/config.dat`, Logs `log/`); Programmdateien kommen
bei jedem Start frisch aus dem Nix-Paket. Neue Version: `version`/`sha256` in `services/iventoy.nix`
(Prüfsummen: `sha256.txt` im [GitHub-Release](https://github.com/ventoy/PXE/releases)).

## HandBrake und MakeMKV

`containers/handbrake-makemkv.nix`, beide mit Oberfläche im Browser (noVNC):

| | Adresse | Image |
|---|---|---|
| HandBrake | http://neotokyo:5800 | `zocker160/handbrake-nvenc` (jlesage-Basis; `jlesage/handbrake` selbst kann kein NVENC) |
| MakeMKV | http://neotokyo:5801 | `jlesage/makemkv` (Beta-Schlüssel holt das Image selbst) |

- **NVENC:** GPU per CDI (`hardware.nvidia-container-toolkit`, `--device=nvidia.com/gpu=all`).
  In HandBrake als Video-Encoder *H.264 (NVEnc)* oder *H.265 (NVEnc)* wählen.
- **Ordner** (SMB-Freigabe `media` → `Transcode`):
  - `Transcode/MakeMKV`: Ausgabe von MakeMKV
  - `Transcode/HandBrake-Watch`: was hier landet, kodiert HandBrake automatisch (Standard-Preset)
  - `Transcode/HandBrake-Output`: Ergebnis
  - Die ganze Mediathek liegt in beiden unter `/storage`, les- und schreibbar: Ergebnis direkt
    nach `Movies`/`TV` speichern, Blu-ray-ISOs aus `ISOs` rippen.
- **Kein optisches Laufwerk eingebaut:** MakeMKV verarbeitet ISO-Dateien und Disc-Ordner. Für
  ein (USB-)Laufwerk `--device=/dev/sr0` und das passende `/dev/sgN` in `extraOptions` ergänzen.
- Einstellungen: `/mnt/fast/services/handbrake` bzw. `…/makemkv`.

## Automatic Ripping Machine (vorbereitet, aus)

`containers/arm.nix`, Schalter `nas.arm.enable` (steht auf `false`, das Blu-ray-Laufwerk ist noch
nicht eingebaut). [ARM](https://github.com/automatic-ripping-machine/automatic-ripping-machine):
Disc einlegen → Titel über OMDb/TMDb erkennen → mit MakeMKV rippen → mit HandBrake (NVENC)
umwandeln → als `Titel (Jahr)` ablegen → auswerfen. Weboberfläche: http://neotokyo:8095.

**Wenn das Laufwerk drin ist:**
1. Prüfen, dass es erkannt wird: `ls /dev/sr*` (meist `/dev/sr0`).
2. `nas.arm.enable = true;` in `configuration.nix`, Rebuild.
3. In ARM unter *Settings*: OMDb-API-Schlüssel eintragen (kostenlos, https://www.omdbapi.com/apikey.aspx),
   HandBrake-Vorlagen auf NVENC stellen (`HB_PRESET_DVD`/`HB_PRESET_BD`, z. B. *H.265 NVENC 1080p*).
4. Testdisc einlegen.

Ablage: `media/Transcode/ARM/` (`raw`, `transcode`, `completed`), Musik-CDs nach `media/Music`.
Läuft mit `--privileged` (eigener udev im Container erkennt eingelegte Discs).

## Lokale KI für Mealie

`services/ai.nix`, Schalter `nas.ai.enable` in `configuration.nix` (eingeschaltet).
Mealie (vmdocker, v3.19+) kann damit Rezepte aus Webseiten, Fotos und Videos
(YouTube/TikTok/Instagram) erstellen und Zutaten zerlegen. Beim Video-Import bekommt die KI
Titel, **Beschreibung** und gesprochenen Text; vorhandene Untertitel (de/en/fr/es/it) ersetzen die
Spracherkennung.

| Dienst | Adresse | Modell |
|---|---|---|
| Ollama (Text + Bild) | `http://10.0.0.5:11434/v1` | `qwen2.5:7b-instruct`, `qwen2.5vl:7b` (~10 GB, `/var/lib/ollama`) |
| Speaches (Spracherkennung) | `http://10.0.0.5:8001/v1` | `Systran/faster-whisper-small` (`/mnt/fast/services/speaches`) |

- Läuft auf der CPU (Quadro P400 zu klein): Text ca. 1–3 min, Foto mehrere Minuten.
- Modelle werden erst bei Bedarf geladen und nach 5 min Leerlauf entladen; Ollama max. 14 GB RAM.
- Ohne Anmeldung, nur über die LAN-Schnittstelle erreichbar.

**Einschalten:**
1. `nas.ai.enable = true;` in `configuration.nix`, dann Rebuild. Der erste Start lädt ~10 GB
   Modelle (`systemctl status ollama-model-loader speaches-model-download`).
2. Mealie → *Einstellungen → KI-Anbieter* (bzw. *AI Providers*) drei Anbieter anlegen,
   API-Schlüssel jeweils beliebig (z. B. `ollama`), Ollama/Speaches ignorieren ihn:

| Name | Base URL | Modell | Timeout (s) | Aufgabe in Mealie |
|---|---|---|---|---|
| Ollama Text | `http://10.0.0.5:11434/v1` | `qwen2.5:7b-instruct` | 600 | allgemein / Rezepte / Zutaten |
| Ollama Bild | `http://10.0.0.5:11434/v1` | `qwen2.5vl:7b` | 900 | Bilder |
| Speaches | `http://10.0.0.5:8001/v1` | `Systran/faster-whisper-small` | 900 | Audio / Transkription |

3. Bei jedem Anbieter *Test* drücken.

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
5. Unter *Allocation* die IP `10.0.0.5` mit den Ports aus `services/gameserver-ports.nix` anlegen.

Ohne SMTP landen Panel-Mails (z. B. Passwort-Reset) nur im Log
(`/var/lib/pterodactyl-panel/storage/logs`). SMTP lässt sich über
`services.pterodactyl.panel.settings` einstellen.

### Gameserver von außen (lmlzr.com)

Der VPS leitet die Spieleports per nftables durch WireGuard an `10.0.0.5` weiter (TCP+UDP,
ersetzt HAProxy). Portliste zentral in `services/gameserver-ports.nix` (öffnet die Firewall),
gleiche Liste auf dem VPS in `vps/nftables-gameforward.conf`. Einrichtung auf dem VPS:
`vps/setup-gameforward.sh` (Rückweg steht im Skript). Neue Ports: beide Dateien anpassen,
im Panel als Allocation anlegen.

| Spiel | Port(s) | Adresse für Spieler |
|---|---|---|
| Minecraft Java | 25565–25600 tcp+udp | `minecraft.lmlzr.com` (SRV-Eintrag pro Server) |
| Minecraft Bedrock | 19132–19133 udp | `minecraft.lmlzr.com:19132` |
| Hytale | 5520–5529 udp | `hytale.lmlzr.com` |
| Satisfactory | 7777 tcp+udp, 8888 tcp | `satisfactory.lmlzr.com` |
| ARK | 7787–7790 udp | `ark.lmlzr.com:7787` (7777 belegt Satisfactory) |
| Don't Starve Together | 10999–11010, 8766–8770, 27018–27019 udp | über die Serverliste |
| CS2 | 27015–27020 tcp+udp | `connect cs2.lmlzr.com` |
| Rust | 28015 + 28017 udp, 28082 tcp (Rust+) | `client.connect rust.lmlzr.com:28015` |

Cloudflare: alle Spiele-Einträge **„DNS only“ (graue Wolke)**, der Cloudflare-Proxy leitet keine
Spiele weiter. Importdatei mit allen Einträgen: `vps/cloudflare-gameserver.zone`
(*DNS → Records → Import and Export*, Haken „Proxy imported DNS records“ **nicht** setzen).
Die Gameserver sehen als Absender `10.10.0.1`, nicht die Spieler-IP.

**IONOS-Firewall** (Cloud Panel → VPS → *Netzwerk → Firewall-Richtlinien*): lässt nur freigegebene
Ports zum VPS durch und muss dieselben Ports enthalten wie `vps/nftables-gameforward.conf`, sonst
kommen die Pakete gar nicht erst an (Symptom: Timeout statt „Verbindung abgelehnt“). Freigegeben:

| Protokoll | Ports |
|---|---|
| TCP | 22, 80, 443, 25565–25600, 7777–7790, 8888, 27015–27020, 28082 |
| UDP | 51820 (WireGuard), 25565–25600, 19132–19133, 5520–5529, 7777–7790, 8766–8770, 10999–11010, 27015–27020, 28015, 28017 |

**Weiterer Minecraft-Server** (z. B. `creative.lmlzr.com`): in Pterodactyl die nächste freie
Allocation (25566, 25567, …) wählen und bei Cloudflare zwei Einträge anlegen, sonst nichts:

```
creative                    1 IN A    217.154.218.53
_minecraft._tcp.creative    1 IN SRV  0 5 25566 creative.lmlzr.com.
```

Bei vielen Servern oder Wechsel ohne Neuverbinden: Velocity-Proxy davor (eine Adresse, `/server <name>`).

**Test von außen** (Ende-zu-Ende über VPS und Tunnel, auch ohne laufenden Gameserver): auf neotokyo
kurz Test-Empfänger starten und von einem anderen Rechner Pakete an `<spiel>.lmlzr.com:<port>` schicken:

```bash
# neotokyo (2 Minuten lang)
nix shell nixpkgs#socat -c sh -c 'timeout 120 socat UDP-RECVFROM:7777,fork SYSTEM:"echo ok" & timeout 120 socat TCP-LISTEN:7777,fork,reuseaddr SYSTEM:"echo ok"'
# anderer Rechner: Antwort "ok" = Port erreichbar
echo ping | nix shell nixpkgs#socat -c socat -T4 - UDP:satisfactory.lmlzr.com:7777
nix shell nixpkgs#socat -c socat -T4 - TCP:satisfactory.lmlzr.com:7777 </dev/null
```
Zuletzt geprüft am 25.10.2026: alle Ports der Tabelle oben erreichbar.

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

## Claude Code Remote Control

`services/claude-rc.nix` startet beim Booten `claude remote-control` im Home-Ordner von lmlzr
(eigene tmux-Sitzung, die Trust-Frage fürs Home-Verzeichnis wird automatisch bestätigt).
Ansehen: `tmux -L claude-rc attach` (verlassen: Strg+B, D) · Neustart: `sudo systemctl restart claude-rc`

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
