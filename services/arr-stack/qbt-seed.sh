#!/usr/bin/env bash
# Seeden pausieren, damit die HDDs schlafen koennen (Downloads laufen weiter, die liegen auf der NVMe).
#   qbt-seed stop   fertige Torrents stoppen und mit Tag "seedpause" markieren
#   qbt-seed start  nur die so markierten Torrents wieder starten (von Hand gestoppte bleiben aus)
# Laeuft auf neotokyo per Timer (qbittorrent.nix) und in Home Assistant als shell_command.
# Braucht curl und jq und einen Zugang ohne Login (qBittorrent: localhost oder AuthSubnetWhitelist).
set -euo pipefail

url="${QBT_URL:-${2:-http://127.0.0.1:8080}}"
api="$url/api/v2"
tag=seedpause

hashes() { curl -fsS "$api/torrents/info?$1" | jq -r "$2 | map(.hash) | join(\"|\")"; }

case "${1:-}" in
  stop)
    # filter=seeding: fertig und nicht gestoppt (uploading, stalledUP, queuedUP, forcedUP)
    h=$(hashes "filter=seeding" '.')
    [ -z "$h" ] && exit 0
    curl -fsS "$api/torrents/addTags" --data-urlencode "hashes=$h" --data-urlencode "tags=$tag"
    curl -fsS "$api/torrents/stop" --data-urlencode "hashes=$h"
    echo "gestoppt: $(tr '|' '\n' <<<"$h" | wc -l)"
    ;;
  start)
    h=$(hashes "tag=$tag" '.')
    [ -z "$h" ] && exit 0
    curl -fsS "$api/torrents/start" --data-urlencode "hashes=$h"
    curl -fsS "$api/torrents/removeTags" --data-urlencode "hashes=$h" --data-urlencode "tags=$tag"
    echo "gestartet: $(tr '|' '\n' <<<"$h" | wc -l)"
    ;;
  *)
    echo "Aufruf: qbt-seed stop|start [URL]" >&2
    exit 2
    ;;
esac
