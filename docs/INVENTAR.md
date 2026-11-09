# Inventar (Stand 09.11.2026)

Hardware und Software von neotokyo, direkt am Rechner abgelesen und mit der Konfiguration
in diesem Repo abgeglichen. Router (Proxmox, OPNsense, vmdocker) und VPS:
[NETZWERK-INVENTAR.md](NETZWERK-INVENTAR.md).

## neotokyo (Server, 10.0.0.5)

### Hardware

| Teil | Modell |
|---|---|
| Mainboard | ASRock B450M Pro4 (BIOS P5.70) |
| CPU | AMD Ryzen 5 3600, 6 Kerne / 12 Threads |
| RAM | 46 GiB nutzbar (vermutlich 48 GB verbaut) |
| Grafik | NVIDIA Quadro P400, 2 GB (Treiber 580.178), für Jellyfin, HandBrake/NVENC und ARM |
| Systemplatte | Crucial BX500 1 TB SATA-SSD (`/boot`, `/`, 8,8 GB Swap) |
| Pool `fast` | WD Blue SN580 1 TB NVMe (928 GB, davon 110 GB belegt) |
| Pool `tank` | 2× Seagate Exos 16 TB (ST16000NM000J) als Mirror (14,5 TB, davon 11,0 TB belegt, 3,6 TB frei) |
| Netzwerk | Realtek RTL8125 2,5 GbE (`enp4s0`, in Benutzung), Realtek RTL8111 1 GbE (`enp5s0`, ungenutzt) |
| Laufwerk | LG BH08LS20 Blu-ray-Brenner (für ARM) |

### System

- NixOS 26.11 (Zokor), Kernel 6.18.57, Konfiguration als Flake in diesem Repo
- ZFS mit automatischen Snapshots, Speicher-Überwachung, Backups (auch von vmdocker),
  Schlafen der Festplatten (hd-idle), Stromsparen, Mail-Versand über Proton
- Werkzeuge: git, gh, neovim, yazi, fzf, htop, bat, fastfetch, ffmpeg, mediainfo, rar,
  wireguard-tools, Claude Code

### Dienste (direkt in NixOS)

| Bereich | Software |
|---|---|
| Medien | Jellyfin, Audiobookshelf, Immich (Fotos; mit Machine Learning, PostgreSQL, Redis) |
| Arr-Stack | Sonarr, Radarr, Lidarr, Prowlarr, FlareSolverr, Seerr (Anfragen) |
| Downloads | qBittorrent über Proton-VPN (eigener Netzwerk-Namespace, Port-Weiterleitung, Watchdog), SABnzbd |
| Spiele | Pterodactyl Panel + Wings (Gameserver; nginx/PHP, MySQL, Redis), Lancache (Spiele-Download-Cache), SteamPrefill (täglich 04:00) |
| Dateien / Netz | Samba (SMB-Freigaben), iVentoy (Netzwerk-Boot) |
| Werkzeuge | Stirling-PDF, Glances (Systemwerte für Homepage), Checkmk-Agent (Überwachung) |

### Docker-Container

| Container | Zweck |
|---|---|
| ARM 2.24.4 | Discs automatisch rippen |
| MakeMKV | ISOs und Discs von Hand rippen |
| HandBrake (NVENC) | Videos umwandeln, mit Watch-Ordner |
| Episode Matcher | DVD-Rips per Spracherkennung einer Folge zuordnen |
| Bookshelf | Bücher (Nachfolger von Readarr) |
| ErsatzTV | eigene TV-Sender aus der Mediathek |
| LiteLLM + PostgreSQL | KI-Schnittstelle |
| LANCache Manager | Spiele-Cache: Statistik, Cache-Browser, Vorladen im Browser (Steam, Epic, Battle.net, Riot) |
| Portainer | Docker-Verwaltung im Browser |

## Andere Geräte

Proxmox-Router mit OPNsense und vmdocker sowie der VPS stehen ausführlich in
[NETZWERK-INVENTAR.md](NETZWERK-INVENTAR.md). Nicht erfasst: Raspberry Pi (EarnApp, WireGuard),
Omada-Switches und -Access-Point, Shelly-Steckdosen (eine misst das ganze Rack).
