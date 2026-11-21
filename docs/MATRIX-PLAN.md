# Matrix: Plan (Stand 05.11.2026, noch nichts gebaut)

Eigener Matrix-Server mit Login, Anrufen (klassisch über TURN und neu über Element Call/LiveKit),
Element Web und Föderation nur mit ausgewählten Servern. Alles läuft zu Hause; der VPS
(example.com, 203.0.113.10) leitet nur weiter.

## Entscheidungen

| Frage | Entscheidung |
|---|---|
| Matrix-Adresse | `@name:example.com` (kurz). **Später nicht mehr änderbar.** |
| Server-URL | `https://matrix.example.com` |
| Anrufe | beide Arten: coturn (1:1, Element Web/Desktop, ältere Apps) **und** LiveKit (Element X, Gruppenanrufe) |
| Föderation | an, aber nur Whitelist: `matrix.org` (später weitere eintragen) |
| Element Web | ja, `chat.example.com`, selbst gehostet |
| Registrierung | aus; Konten per `register_new_matrix_user` |
| Wo läuft was | alles zu Hause, VPS nur Weiterleitung; im Heimnetz direkt erreichbar, ohne Umweg über den VPS |
| Nur Matrix über VPS | eigener Tunnel trägt nur Matrix-Verkehr, keine Standardroute über den VPS |
| Gerät | **offen**: neotokyo, eigene VM auf Proxmox oder eigener Mini-PC (siehe unten) |

## Bestandsaufnahme (05.11.2026)

**DNS (Cloudflare, graue Wolke, alle → 203.0.113.10):** `example.com`, `turn`, `matrix`,
`livekit`, `chat` sind gesetzt.

**VPS:**
- 1 vCPU, 847 MB RAM (466 MB frei), 3,7 GB Platte frei. Darum dort nichts Großes laufen lassen.
- **coturn:**
  - nur Reste: Paket entfernt (`dpkg` Status `rc`), `/etc/turnserver.conf` ist noch da.
  - Fehler in der Datei: `max-port=48170` < `min-port=49160`, feste `user=`-Anmeldung statt gemeinsamem Schlüssel.
  - → wird nicht mehr gebraucht, coturn läuft zu Hause.
- **nginx-Seite `matrix`:** alt (Feb. 2026), leitet an `10.0.0.7:8008` (gibt es nicht).
  Liefert eigene `.well-known` mit `m.server matrix.example.com:443`.
- **`example.com` über HTTPS:** läuft über die Standard-Seite (`/var/www/html`) mit dem alten Zertifikat
  `matrix.example.com` (deckt offenbar auch `example.com` ab).
- **WireGuard `wg0`:** `10.10.0.1/24`, Port 51820. Peers: Router .2 (+10.0.0.0/24), Raspberry .3, Thinkpad .4, Pixel .10.
- **Bestehende Weiterleitung der Gameserver (`nft-gameforward`):** benutzt `masquerade`.
  **Für TURN/LiveKit ungeeignet** (siehe unten).

**neotokyo:**
- **Port 443 auf `10.0.0.5`** belegt der Lancache (reicht HTTPS je nach Name weiter).
  nginx läuft schon (Lancache, Pterodactyl auf 8090).
- **PostgreSQL 18:** schon da (Immich).
- **Firewall:** iptables, `checkReversePath = "loose"` (gut für den Tunnel).
- **Freie Ports (geprüft):** 8008, 8009, 8097, 7880–7882, 3478, 49160–49200. 8095 ist belegt.
- **NixOS-Module vorhanden** (nixos-unstable): `services.matrix-synapse` (1.162.0), `services.coturn`,
  `services.livekit`, `services.lk-jwt-service`, `networking.wg-quick`, `pkgs.element-web` (1.12.30).

## Warum ein eigener Tunnel mit echter Absender-IP

Die Gameserver-Weiterleitung ersetzt den Absender durch `10.10.0.1`. Für TURN geht das nicht:
coturn prüft bei eingehenden Paketen der Gegenseite deren IP gegen die „Erlaubnis“, die der Anrufer
angelegt hat. Mit ersetztem Absender kommt alles von `10.10.0.1` und wird verworfen. LiveKit würde
alle Teilnehmer als dieselbe IP sehen.

Lösung:
- Der Matrix-Rechner bekommt einen **eigenen WireGuard-Zugang** zum VPS: `wg-vps`, `10.10.0.5`.
- Der VPS leitet mit DNAT **ohne masquerade** an `10.10.0.5` weiter.
- Antworten mit Absender `10.10.0.5` schickt der Matrix-Rechner per eigener Routing-Tabelle zurück in den Tunnel (`ip rule from 10.10.0.5 lookup 51820`).
- Aller andere Verkehr bleibt im normalen Routing über den Router.

## Aufbau

```
Internet ──> VPS 203.0.113.10
              ├ nginx (HTTPS, eigene Zertifikate) ─┐
              │   matrix.example.com                  │
              │   example.com/.well-known/matrix/*    │
              │   livekit.example.com                 ├─ WireGuard wg-vps ─> Matrix-Rechner 10.10.0.5
              │   chat.example.com                    │  (nur Matrix,         ├ Synapse       :8008
              └ nftables, DNAT ohne masquerade ─────┘   echte Absender-IP)  ├ lk-jwt        :8009
                  3478 tcp+udp      coturn                                  ├ Element Web   :8097
                  49160–49200 udp   coturn Relay                            ├ LiveKit       :7880 (WS), 7881 tcp, 7882 udp
                  7881 tcp, 7882 udp LiveKit                                ├ coturn        :3478, Relay 49160–49200
                                                                            └ PostgreSQL

Heimnetz ──> Pi-hole: matrix/livekit/chat/turn.example.com → LAN-IP des Matrix-Rechners
              └ nginx dort mit eigenem Zertifikat (Let's Encrypt per Cloudflare-DNS)
```

## Teil A: Matrix-Rechner (NixOS, neue Datei `services/matrix.nix`)

### A1. WireGuard `wg-vps`
- `networking.wg-quick.interfaces.wg-vps`:
  - `address = [ "10.10.0.5/32" ]`, `generatePrivateKeyFile = true`, privater Schlüssel unter `/etc/secrets/wg-vps.key`.
  - `table = "51820"`, Peer VPS: `endpoint = "example.com:51820"`, `allowedIPs = [ "0.0.0.0/0" ]`, `persistentKeepalive = 25`.
  - `postUp`: `ip rule add from 10.10.0.5 lookup 51820 priority 100` (und passend `preDown`).
- Damit geht **nur** Verkehr mit Absender 10.10.0.5 durch den Tunnel.
- **Braucht:** öffentlichen Schlüssel des VPS (`sudo wg show wg0 public-key`).

### A2. Schlüssel (nicht im Repo)
- Ein Oneshot-Dienst `matrix-secrets` erzeugt beim ersten Start unter `/var/lib/matrix-secrets/`:
  - `synapse.yaml` mit `registration_shared_secret`, `turn_shared_secret`, `macaroon_secret_key`, `form_secret` (lesbar für `matrix-synapse`)
  - `turn-secret` (derselbe TURN-Schlüssel, für coturn `static-auth-secret-file`)
  - `livekit.keys` im Format `<name>: <secret>` (für LiveKit `keyFile` und lk-jwt `keyFile`, beide per `LoadCredential`)
- Vorbild: `containers/litellm.nix` (`rand`-Funktion, Datei nur anlegen, wenn sie fehlt).

### A3. PostgreSQL
- Synapse verlangt die Sortierung `C`. `ensureDatabases` legt mit der Standard-Locale an → stattdessen:
  - `ensureUsers = [ { name = "matrix-synapse"; } ]`
  - Oneshot vor Synapse: `createdb --encoding=UTF8 --locale=C --template=template0 --owner=matrix-synapse matrix-synapse`, wenn die DB noch nicht existiert.
- Verbindung über Unix-Socket `/run/postgresql` (Peer-Auth, kein Passwort).
- Auf neotokyo: die vorhandene PostgreSQL (Immich) mitbenutzen. Auf eigenem Gerät: neu.

### A4. Synapse (`services.matrix-synapse`)
```nix
settings = {
  server_name = "example.com";
  public_baseurl = "https://matrix.example.com/";
  serve_server_wellknown = true;          # /.well-known/matrix/server → matrix.example.com:443
  listeners = [{
    port = 8008; bind_addresses = [ "0.0.0.0" ]; type = "http"; tls = false;
    x_forwarded = true;                    # echte Client-IP aus X-Forwarded-For (VPS/lokales nginx)
    resources = [{ names = [ "client" "federation" ]; compress = false; }];
  }];
  database = { name = "psycopg2"; args = { user = "matrix-synapse"; database = "matrix-synapse"; host = "/run/postgresql"; }; };
  media_store_path = "<daten>/media";      # neotokyo: /mnt/fast/services/matrix/media
  enable_registration = false;
  federation_domain_whitelist = [ "matrix.org" ];
  turn_uris = [ "turn:turn.example.com:3478?transport=udp" "turn:turn.example.com:3478?transport=tcp" ];
  turn_user_lifetime = "1h";
  # Element Call / MatrixRTC
  experimental_features = { msc3266_enabled = true; msc4222_enabled = true; };
  max_event_delay_duration = "24h";
  rc_message = { per_second = 0.5; burst_count = 30; };
  rc_delayed_event_mgmt = { per_second = 1; burst_count = 20; };
  extra_well_known_client_content."org.matrix.msc4143.rtc_foci" = [
    { type = "livekit"; livekit_service_url = "https://livekit.example.com/livekit/jwt"; }
  ];
  url_preview_enabled = false;
};
extraConfigFiles = [ "/var/lib/matrix-secrets/synapse.yaml" ];
```
- Synapse liefert `/.well-known/matrix/client` selbst aus (mit `base_url` und `rtc_foci`). Der VPS reicht `example.com/.well-known/matrix/` nur durch.
- Hinweis: Mit Whitelist sind öffentliche Räume anderer Server nicht erreichbar; große matrix.org-Räume brauchen viel RAM/DB.
- **Konto anlegen:** `register_new_matrix_user -k <registration_shared_secret> http://localhost:8008`.
  Der Schlüssel liegt in `synapse.yaml` (`-c` mit der Datei geht auch).

### A5. coturn (`services.coturn`)
- `listening-ips = [ "10.10.0.5" "<LAN-IP>" ]`, `relay-ips = [ "10.10.0.5" ]`
- `extraConfig`: `external-ip=203.0.113.10/10.10.0.5`
- `use-auth-secret = true`, `static-auth-secret-file = /var/lib/matrix-secrets/turn-secret`, `realm = "turn.example.com"`
- `min-port = 49160`, `max-port = 49200`, `no-tls`, `no-dtls`, `no-cli`
- Heimnetz sperren:
  - `denied-peer-ip` für 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 127.0.0.0/8, 0.0.0.0/8
  - `no-multicast-peers`
- Systemd: `after`/`bindsTo` `wg-quick-wg-vps.service` (hört auf 10.10.0.5).
- TURN über TLS (5349) erst mal weg; nachrüsten, wenn ein Netz nur 443/TLS erlaubt.

### A6. LiveKit + lk-jwt-service
- `services.livekit`:
  - `keyFile = /var/lib/matrix-secrets/livekit.keys`
  - `settings`:
    - `port = 7880`
    - `rtc.tcp_port = 7881`, `rtc.udp_port = 7882` (ein UDP-Port für alles, statt Bereich)
    - `rtc.node_ip = "203.0.113.10"`, `rtc.use_external_ip = false`
- **Beim Test prüfen:** Bietet LiveKit zusätzlich die LAN-IP an, damit Geräte zu Hause nicht über den VPS gehen?
- `services.lk-jwt-service`:
  - `port = 8009`, `livekitUrl = "wss://livekit.example.com"`, `keyFile` = dieselbe Datei
  - Räume anlegen nur für `example.com`: `LIVEKIT_FULL_ACCESS_HOMESERVERS=example.com` per `systemd.services.lk-jwt-service.environment`
- `openFirewall` nicht benutzen (öffnet überall), Ports selbst pro Interface.

### A7. Element Web
- `pkgs.element-web.override { conf = { … }; }`:
  - `default_server_config."m.homeserver" = { base_url = "https://matrix.example.com"; server_name = "example.com"; }`
  - `disable_custom_urls = true`, `disable_guests = true`
  - `element_call.use_exclusively = true` (Gruppenanrufe über LiveKit)
- **Auf neotokyo:** als weitere Seite im vorhandenen nginx auf `0.0.0.0:8097` (wie Pterodactyl auf 8090).
- **Auf eigenem Gerät:** nginx direkt auf 443.

### A8. Lokaler Zugang im Heimnetz (ohne VPS)
- Zertifikate auf dem Matrix-Rechner: `security.acme` mit `dnsProvider = "cloudflare"` für `matrix`, `livekit`, `chat` und `turn.example.com`.
  - **Braucht:** Cloudflare-API-Token (Zone → DNS → Bearbeiten, nur `example.com`).
  - Ablage: `/etc/secrets/cloudflare-dns.env` mit `CF_DNS_API_TOKEN=…`, `chmod 600`. Den Wert nie ins Repo.
- nginx (HTTPS) für diese Namen → Synapse 8008, LiveKit 7880, lk-jwt 8009, Element 8097.
- **Nur auf neotokyo:** Port 443 auf 10.0.0.5 gehört dem Lancache.
  - Dessen `streamConfig` (`ssl_preread`) per `lib.mkForce` um eine `map` erweitern: diese vier Namen → lokales nginx (z. B. `127.0.0.1:8448`), alles andere wie bisher `$ssl_preread_server_name:443`.
  - Bei jedem Update von `lancache-nix` prüfen, ob die übernommene Konfiguration noch passt.
- **Auf eigenem Gerät/VM:** entfällt, eigene IP mit eigenem Port 443.
- Pi-hole (vmdocker): lokale DNS-Einträge `matrix`, `livekit`, `chat`, `turn.example.com` → LAN-IP des Matrix-Rechners.
  - `example.com` selbst bleibt beim VPS (nur `.well-known`).
  - Danach `docker exec pihole pihole reloaddns` (alte NXDOMAIN-Einträge im Cache).

### A9. Firewall
- `wg-vps`:
  - tcp 8008, 8009, 8097, 7880, 7881, 3478
  - udp 3478, 7882, 49160–49200
- LAN-Interface:
  - tcp 443 (eigenes Gerät) bzw. über Lancache, sowie 3478 und 7881
  - udp 3478, 7882, 49160–49200

## Teil B: VPS (Dateien im Repo unter `vps/`, du führst sie mit sudo aus)

### B1. WireGuard-Peer
- In `/etc/wireguard/wg0.conf`:
  ```
  [Peer]
  # Matrix-Rechner
  PublicKey = <öffentlicher Schlüssel aus /etc/secrets/wg-vps.key, nach dem Rebuild>
  AllowedIPs = 10.10.0.5/32
  ```
- Dann `sudo wg syncconf wg0 <(wg-quick strip wg0)` oder `systemctl restart wg-quick@wg0`. Ein Neustart unterbricht kurz Handy und Router.

### B2. nftables `vps/nftables-matrixforward.conf` + Dienst `nft-matrixforward`
- Aufbau wie `nftables-gameforward.conf`, eigene Tabelle `ip matrixforward`.
- **DNAT ohne masquerade:**
  - `iifname "ens6"`: udp 3478, 7882, 49160–49200 → 10.10.0.5
  - `iifname "ens6"`: tcp 3478, 7881 → 10.10.0.5
- **Haarnadel für Relay↔Relay** (zwei Anrufer, beide über TURN):
  - `iifname "wg0" ip saddr 10.10.0.5 ip daddr 203.0.113.10 udp dport 49160-49200` → dnat zu 10.10.0.5
  - dazu snat auf 203.0.113.10, damit coturn die Gegenseite als öffentliche Adresse sieht
- MSS-Anpassung für TCP wie bei gameforward.
- `ip_forward=1` ist schon gesetzt (gameforward).

### B3. nginx `vps/nginx-matrix.conf` (ersetzt `/etc/nginx/sites-available/matrix`)
- `matrix.example.com` → `http://10.10.0.5:8008`
  - `include snippets/homelab-proxy.conf`, `client_max_body_size 100m`
  - Ohne doppelte `proxy_read_timeout`, sonst meldet nginx „duplicate“.
- `example.com`: nur `location /.well-known/matrix/` → `http://10.10.0.5:8008`, Rest wie bisher `/var/www/html`
- `livekit.example.com`:
  - `location /` → `http://10.10.0.5:7880` (WebSocket)
  - `location /livekit/jwt/` → `http://10.10.0.5:8009/`
- `chat.example.com` → `http://10.10.0.5:8097`
- Erst nur Port 80, dann `sudo certbot --nginx -d matrix.example.com -d example.com -d livekit.example.com -d chat.example.com`.
  Certbot erst, wenn die Datei aktiv ist, sonst schreibt es in `default`.
- `example.com` hat danach einen eigenen 443-Block; der alte certbot-Block in `default` bleibt für den Rest.

### B4. Aufräumen
- `sudo apt purge coturn`, `/etc/turnserver.conf` entfernen.
- Alte Seite `matrix` erst ersetzen, wenn die neue funktioniert. Das alte Zertifikat `matrix.example.com` behalten, bis certbot die neuen ausgestellt hat.

### B5. Firewall beim Anbieter (IONOS-Cloud-Panel; ufw ist aus)
- tcp: 3478, 7881 (443 ist offen)
- udp: 3478, 7882, 49160–49200
- 8448 nicht nötig (Föderation über `.well-known` auf 443)

## Teil C: Test

1. **`.well-known`** von außen:
   - `curl https://example.com/.well-known/matrix/server` → `matrix.example.com:443`
   - `curl https://example.com/.well-known/matrix/client` → `base_url` und `rtc_foci`
2. `curl https://matrix.example.com/_matrix/client/versions`, einmal von außen (Handy im Mobilfunk) und einmal im Heimnetz (muss die LAN-IP treffen: `curl -v`).
3. **Föderation:** https://federationtester.matrix.org mit `example.com`.
4. Konto anlegen, in Element Web (`chat.example.com`) und Element X anmelden.
5. **TURN:** Mit Zugangstoken `GET /_matrix/client/v3/voip/turnServer` aufrufen, das muss `uris`/`username`/`password` liefern.
   Dann mit diesen Daten das Trickle-ICE-Testtool im Browser benutzen: Ein `relay`-Kandidat mit 203.0.113.10 muss erscheinen.
6. **LiveKit:** `curl https://livekit.example.com/livekit/jwt/healthz` (o. ä.); dann ein Element-Call-Anruf mit 2 Geräten.
7. **Testanrufe:**
   - Handy (Mobilfunk) ↔ PC (Heimnetz), 1:1 (TURN) und Gruppe (LiveKit)
   - Beide zu Hause: Der Verkehr darf nicht über den VPS gehen (`wg show` auf dem VPS, Zähler für 10.10.0.5).
8. **Routing-Kontrolle:** Auf dem Matrix-Rechner zeigt `curl ifconfig.me` weiter die Heim-IP, nicht die VPS-IP.

## Ressourcen und Gerät

| Dienst | RAM | CPU |
|---|---|---|
| Synapse | 300 MB – 1,5 GB (große matrix.org-Räume am meisten) | gering, Spitzen beim Betreten großer Räume |
| PostgreSQL | 200–500 MB | gering |
| coturn | ~20 MB | fast nichts |
| LiveKit + JWT | 100–300 MB | gering bis mittel bei Video (verteilt nur, wandelt nicht um) |
| Element Web | – | – (feste Dateien) |
| System | ~300 MB | – |

- **Empfehlung eigenes Gerät:** 4 Kerne (N100/N150), **8 GB RAM**, SSD 128–256 GB (keine HDD/SD-Karte), 1 Gbit. Strom etwa 6–10 W.
- **Bandbreite:** Videoanruf ca. 1–3 Mbit/s pro Person und Richtung über den Heimanschluss (Anrufe von außen gehen über VPS und Tunnel).

Möglichkeiten:
1. **Mini-PC N100**, 8–16 GB, 256-GB-SSD: etwa 130–200 €. Empfehlung.
2. **Raspberry Pi 5 8 GB + NVMe-Aufsatz:** etwa 120–150 €. Geht, knapper bei großen Räumen.
3. **VM auf Proxmox (i5-8500T)**, 2–4 Kerne, 4–8 GB: kein Geld, kaum mehr Strom. Freien RAM vorher prüfen.
4. **neotokyo:** geht, aber Port-443-Umweg über Lancache (A8), und jeder Rebuild/Neustart unterbricht Anrufe.

Vorteil eigenes Gerät/VM:
- eigene LAN-IP (z. B. 10.0.0.8, am 05.11. per Ping frei) mit eigenem Port 443, kein Lancache-Umbau
- Rebuilds von neotokyo stören nicht
- `services/matrix.nix` lässt sich fast unverändert auf einem eigenen NixOS-Rechner verwenden

## Offen / von dir zu liefern

- [ ] Gerät entscheiden (neotokyo / VM / Mini-PC); bei neuem Gerät NixOS installieren und Flake-Host anlegen
- [ ] Öffentlicher WireGuard-Schlüssel des VPS: `sudo wg show wg0 public-key`
- [ ] Cloudflare-API-Token (DNS bearbeiten, nur `example.com`) → `/etc/secrets/cloudflare-dns.env`
- [ ] Ports im IONOS-Panel freigeben (B5)
- [ ] Pi-hole-Einträge (A8)
- [ ] Weitere Server für die Föderations-Whitelist, falls gewünscht

## Reihenfolge beim Bauen

1. Matrix-Rechner: `services/matrix.nix` (A1–A9), Rebuild. Danach öffentlichen Schlüssel aus `/etc/secrets/wg-vps.key` ablesen (`wg pubkey < …`).
2. VPS: Peer (B1), nftables (B2), nginx + certbot (B3), Anbieter-Firewall (B5).
3. Pi-hole-Einträge (A8).
4. Tests (C), Konto anlegen.
5. Aufräumen (B4), README-Abschnitt und Ports-Tabelle ergänzen.
