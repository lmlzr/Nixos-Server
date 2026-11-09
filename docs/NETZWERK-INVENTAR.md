# Netzwerk-Inventar (Stand 09.11.2026)

Router (Proxmox-Host mit OPNsense und vmdocker) und VPS. Abgelesen direkt auf den Geräten
(Proxmox und VPS per SSH, OPNsense per SSH als Benutzer `claude`). Server neotokyo: siehe
[INVENTAR.md](INVENTAR.md).

## Router: Proxmox-Host `router` (10.0.0.2)

### Hardware

| Teil | Modell |
|---|---|
| Gerät | Lenovo ThinkCentre Tiny (Typ 10T8S1MJ00, Mainboard 312D) |
| CPU | Intel Core i5-8500T, 6 Kerne / 6 Threads, 2,1 GHz (kein APICv, siehe OPNsense-Interrupt-Fix) |
| Grafik | Intel UHD Graphics 630 (onboard) |
| RAM | 24 GB: 1× 16 GB DDR4-3200 (LD4AS016G-3200ST) + 1× 8 GB DDR4-2666 (SK hynix HMA81GS6CJR8N-VK), läuft mit 2666 |
| SSD | Samsung PM981 256 GB NVMe (MZVLB256HAHQ) |
| Netzwerk onboard | Intel I219-V (`nic0`, Bridge `vmbr0` = Management und vmdocker). TSO/GSO/EEE aus wegen „Hardware Unit Hang“ (Ausfall 31.10.2026) |
| Netzwerk Zusatzkarte | 2× Intel I226-V 2,5 GbE, beide per PCI-Passthrough an OPNsense (WAN/LAN) |

### Software

- Proxmox VE 9.2.2, Kernel 7.0.2-6-pve
- Speicher: `local` (Verzeichnis, 68 GB, 46 % belegt), `local-lvm` (LVM-Thin, 141 GB, 53 % belegt)
- Bridges: `vmbr0` (10.0.0.2/24, an `nic0`), `virtlan` (intern zwischen OPNsense und Host)
- RAM fast voll ausgelastet (20 von 23 GiB belegt; vmdocker 16 GB + OPNsense 4 GB fest zugeteilt)

### VMs

| VMID | Name | CPU | RAM | Platte | Netzwerk | System |
|---|---|---|---|---|---|---|
| 100 | OPNsense | 2 Kerne (host) | 4 GB (kein Ballooning) | 20 GB | 2× I226-V durchgereicht + virtio an `virtlan` | OPNsense 26.1.6 (FreeBSD 14.3) |
| 101 | vmdocker (10.0.0.3) | 4 Kerne (host) | 16 GB | 150 GB | virtio an `vmbr0` | Debian 13 (trixie), QEMU-Gastagent an |

### OPNsense (10.0.0.1)

- OPNsense 26.1.6_2, FreeBSD 14.3-RELEASE-p10
- Schnittstellen: `igc0`, `igc1` (die beiden I226-V), `vtnet0` (virtio), `wg0` (WireGuard zum VPS)
- Tunables in `/boot/loader.conf.local`: `hw.igc.max_interrupt_rate=4000`, `hw.igc.enable_aim=0`
  (CPU-Last bei Downloads von 1,1–1,5 auf ~0,3 Kerne gesenkt)
- Firewall-Logging aus, Traffic Shaper (Upload ~38 Mbit/s)

### vmdocker (10.0.0.3), Docker-Container

| Container | Zweck |
|---|---|
| Home Assistant | Hausautomatisierung |
| Pi-hole | DNS und Werbeblocker fürs ganze Netz |
| Omada Controller 6.2 | Verwaltung von Switches und Access-Point |
| Homepage | Startseite mit allen Diensten |
| Checkmk 2.5 (Community) | Überwachung |
| Mealie | Rezepte |
| ntfy | Push-Benachrichtigungen |
| Music Assistant | Musik |
| Karakeep (+ Chrome, Meilisearch) | Lesezeichen |
| Nutritrace | Ernährung |
| Firefox | Browser im Browser |
| Syncthing | Dateisynchronisation |
| Portainer | Docker-Verwaltung |

## VPS (öffentlicher Einstieg)

### Hardware (virtuell)

| Teil | Wert |
|---|---|
| Anbieter | IONOS, KVM |
| CPU | 1 vCPU, AMD EPYC (Milan) |
| RAM | 847 MiB, kein Swap |
| Platte | 10 GB (9,7 GB nutzbar, 62 % belegt) |
| Netzwerk | `ens6` mit öffentlicher IPv4 (/32, kein öffentliches IPv6), `wg0` 10.10.0.1/24 |

### Software

- Debian 13 (trixie), Kernel 6.12.94
- **nginx 1.26** mit **certbot 4.0** (Let's Encrypt, Erneuerung per Timer): Weiterleitung der Heimdienste
  per WireGuard. Seiten: homelab (Sammeldatei), jellyfin, immich, checkmk, wings, firefox (mit Login),
  musicassistant, matrix (alt, Ziel existiert nicht mehr), default
- **WireGuard** (`wg-quick@wg0`): Peers Router, Raspberry Pi, Thinkpad, Handy
- **nftables**: `nft-gameforward` (Gameserver-Ports an neotokyo), `nft-phone-nat` (Handy ins Heimnetz)
- **ufw** aktiv, **exim4** (lokale Mails), **qrencode** (WireGuard-QR-Codes)
- Installiert, aber aus: **HAProxy** (früher Minecraft-Weiterleitung). Docker ist nicht installiert.

## Nicht abgefragt

- Omada-Switches und -Access-Point (Modelle über den Omada Controller auslesbar)
- Raspberry Pi (EarnApp, WireGuard)
- Shelly-Steckdosen (eine Gen3, zwei Gen1; eine davon misst den ganzen Rack-Strom)
