#!/usr/bin/env bash
# Auf dem VPS ausfuehren: sudo bash ~/setup-gameforward.sh
# Ersetzt HAProxy (nur TCP 25565) durch nftables-Weiterleitung aller Spieleports (TCP+UDP).
# Rueckweg: sudo systemctl disable --now nft-gameforward && sudo systemctl enable --now haproxy
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "mit sudo starten"; exit 1; }
cd "$(dirname "$0")"

echo "==> nftables installieren"
command -v nft >/dev/null || { apt-get update -qq && apt-get install -y -qq nftables; }

echo "==> Regeln pruefen und installieren"
nft -c -f nftables-gameforward.conf
install -m 0644 nftables-gameforward.conf /etc/nftables-gameforward.conf

cat > /etc/systemd/system/nft-gameforward.service <<'EOF'
[Unit]
Description=Spieleports per WireGuard an neotokyo weiterleiten
After=network-online.target wg-quick@wg0.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables-gameforward.conf
ExecStop=/usr/sbin/nft delete table ip gameforward

[Install]
WantedBy=multi-user.target
EOF

echo "==> IPv4-Weiterleitung dauerhaft an"
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-gameforward.conf
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "==> HAProxy aus, Weiterleitung an"
systemctl disable --now haproxy || true
systemctl daemon-reload
systemctl enable --now nft-gameforward
nft list table ip gameforward | head -20
echo
echo "Fertig. Test von aussen: minecraft auf lmlzr.com:25565"
