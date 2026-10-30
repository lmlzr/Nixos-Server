#!/usr/bin/env bash
# Auf dem VPS ausfuehren: sudo bash ~/setup-phone-vpn.sh [geraetename]
#
# Handy (oder Laptop) per WireGuard ueber den VPS ins Heimnetz 10.0.0.0/24.
#   ohne Argument: nur Diagnose + Weiterleitung reparieren
#   mit Name:      zusaetzlich neues Geraet anlegen, Config + QR-Code ausgeben
#
# Warum es vorher nicht ging:
#   1. ufw verwirft Weiterleitungen standardmaessig. Handy -> wg0 -> wg0 -> Heimnetz ist eine
#      Weiterleitung auf demselben Interface und braucht eine eigene "ufw route"-Regel.
#   2. Das Heimnetz kennt den Rueckweg zu den Handy-Adressen (10.10.0.x) nicht. Deshalb werden
#      sie hier hinter 10.10.0.1 versteckt (masquerade), wie schon bei den Spieleports.
# Rueckweg: sudo systemctl disable --now nft-phone-nat; sudo ufw route delete allow in on wg0 out on wg0
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "mit sudo starten"; exit 1; }
WG=wg0
CONF=/etc/wireguard/$WG.conf
HOME_NET=10.0.0.0/24
VPN_NET=10.10.0.0/24
VPN_IP=10.10.0.1
ENDPOINT=217.154.218.53:51820
DNS=10.0.0.3 # Pi-hole

echo "==> WireGuard-Peers"
wg show $WG | sed -E 's/(preshared key: ).*/\1(verborgen)/'

echo "==> ufw: Weiterleitung wg0 -> wg0 erlauben"
ufw route allow in on $WG out on $WG >/dev/null && ufw status | grep -E "on $WG" || true

echo "==> NAT fuer Geraete -> Heimnetz (dauerhaft per systemd)"
cat > /etc/nftables-phone-nat.conf <<EOF
table ip phonenat
delete table ip phonenat
table ip phonenat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "$WG" ip saddr $VPN_NET ip saddr != $VPN_IP ip daddr $HOME_NET masquerade
  }
}
EOF
cat > /etc/systemd/system/nft-phone-nat.service <<EOF
[Unit]
Description=WireGuard-Geraete ins Heimnetz (NAT auf $VPN_IP)
After=network-online.target wg-quick@$WG.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables-phone-nat.conf
ExecStop=/usr/sbin/nft delete table ip phonenat

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now nft-phone-nat >/dev/null
systemctl restart nft-phone-nat
nft list table ip phonenat | grep masquerade

[ $# -ge 1 ] || { echo; echo "Fertig. Neues Geraet anlegen: sudo bash $0 <name>"; exit 0; }

NAME=$1
echo "==> Neues Geraet: $NAME"
command -v qrencode >/dev/null || { apt-get update -qq && apt-get install -y -qq qrencode; }
used=$(grep -oE '10\.10\.0\.[0-9]+' "$CONF"; wg show $WG allowed-ips | grep -oE '10\.10\.0\.[0-9]+')
n=10; while echo "$used" | grep -qx "10.10.0.$n"; do n=$((n + 1)); done
IP=10.10.0.$n
umask 077
PRIV=$(wg genkey); PUB=$(echo "$PRIV" | wg pubkey); PSK=$(wg genpsk)
SERVER_PUB=$(wg show $WG public-key)
cp "$CONF" "$CONF.bak-$(date +%Y%m%d-%H%M%S)"
cat >> "$CONF" <<EOF

[Peer]
# $NAME
PublicKey = $PUB
PresharedKey = $PSK
AllowedIPs = $IP/32
EOF
wg set $WG peer "$PUB" preshared-key <(echo "$PSK") allowed-ips "$IP/32"

CLIENT=/root/wg-$NAME.conf
cat > "$CLIENT" <<EOF
[Interface]
PrivateKey = $PRIV
Address = $IP/32
DNS = $DNS

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $PSK
Endpoint = $ENDPOINT
AllowedIPs = $HOME_NET, $VPN_NET
PersistentKeepalive = 25
EOF
echo "Config: $CLIENT  (Adresse $IP)"
echo "In der WireGuard-App: + -> QR-Code scannen"
qrencode -t ansiutf8 < "$CLIENT"
