{ config, lib, pkgs, ... }:

# Suwayomi: Manga-Server mit den Erweiterungen von Mihon/Tachiyomi. Haelt die Manga-Bibliothek
# aktuell: Serien abonnieren, neue (und fehlende) Kapitel werden als CBZ geladen.
# Nativ aus nixpkgs, kein Container. http://10.0.0.5:4567 (nur Heimnetz, ohne Login)
#
# Ablauf: Suwayomi laedt nach /mnt/tank/media/Manga-Downloads, manga-import (taeglich) legt
# davon Hardlinks im Serienordner der Manga-Bibliothek an ("<Serie> Ch.NNN.cbz"), Komga findet
# sie, weil manga-import danach einen Scan der Bibliotheken Manga und Comics anstoesst
# (Komga-API-Key nur root-lesbar in /var/lib/secrets/komga-scan.key). Abweichende Serientitel in Manga-Downloads/zuordnung.json eintragen.
# Cloudflare-geschuetzte Quellen laufen ueber FlareSolverr (arr-stack).
let
  cfg = config.nas;
  port = 4567;
  dataDir = "${cfg.servicesDir}/suwayomi";
  downloads = "${cfg.mediaDir}/Manga-Downloads";
  library = "${cfg.mediaDir}/Manga";
  # Nach dem Import Komga scannen lassen (sonst nur 1x taeglich zu wechselnder Uhrzeit).
  # Comics gleich mit, die Platten laufen um die Zeit ohnehin (Kapowarr legt Hefte direkt ab).
  komgaScan = pkgs.writeShellScript "komga-scan" ''
    key=$(cat "$CREDENTIALS_DIRECTORY/komga")
    api=http://127.0.0.1:25600/api/v1/libraries
    for name in Manga Comics; do
      id=$(${pkgs.curl}/bin/curl -fsS -H "X-API-Key: $key" $api \
        | ${pkgs.jq}/bin/jq -r --arg n "$name" '.[] | select(.name == $n) | .id')
      if [ -n "$id" ] && ${pkgs.curl}/bin/curl -fsS -X POST -H "X-API-Key: $key" "$api/$id/scan"; then
        echo "Komga-Scan gestartet: $name"
      else
        echo "Komga-Scan fehlgeschlagen: $name"
      fi
    done
  '';
in
{
  services.suwayomi-server = {
    enable = true;
    # nixpkgs hat 2.1: kann das neue Erweiterungsverzeichnis (index.pb, "Outdated App") nicht lesen
    package = pkgs.suwayomi-server.overrideAttrs (old: rec {
      version = "2.4.2366";
      src = pkgs.fetchurl {
        url = "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v${version}/Suwayomi-Server-v${version}.jar";
        hash = "sha256-r5/rIK+dfr6eMHaebG68f8erHERziNQuAoCx2l/ge/0=";
      };
    });
    inherit dataDir;
    group = "media"; # Bibliothek gehoert root:media (2775/664)
    settings.server = {
      inherit port;
      downloadAsCbz = true;
      downloadsPath = downloads;
      autoDownloadNewChapters = true;
      # Gelesen wird in Komga, fuer Suwayomi ist alles "ungelesen/nicht angefangen": ohne diese
      # zwei ueberspringt die taegliche Suche jede Serie (so geschehen bis 2026-11-15)
      excludeUnreadChapters = false;
      excludeNotStarted = false;
      # Einmal am Tag nach neuen Kapiteln suchen (weckt sonst die HDDs, siehe hd-idle)
      globalUpdateInterval = 24;
      extensionStores = [ "https://raw.githubusercontent.com/keiyoushi/extensions/repo/repo.json" ];
      flareSolverrEnabled = true;
      flareSolverrUrl = "http://127.0.0.1:8191";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 suwayomi media -"
    # Zwischenordner fuer server.conf (.local/share/Tachidesk, Regel im Modul): muessen
    # suwayomi gehoeren, sonst bricht tmpfiles mit "unsafe path transition" ab
    "d ${dataDir}/.local 0750 suwayomi media -"
    "d ${dataDir}/.local/share 0750 suwayomi media -"
    "d ${downloads} 2775 suwayomi media -"
  ];

  systemd.services.suwayomi-server = {
    unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir ];
    serviceConfig.UMask = "0002";
  };

  systemd.services.manga-import = {
    description = "Von Suwayomi geladene Kapitel in die Manga-Bibliothek uebernehmen";
    unitConfig.RequiresMountsFor = [ cfg.mediaDir ];
    after = [ "komga.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Hardlinks gehen nur als Besitzer der Dateien (fs.protected_hardlinks)
      User = "suwayomi";
      Group = "media";
      UMask = "0002";
      # Pillow: Manganato-Seitenstreifen wieder zusammenkleben (siehe manga-import.py)
      ExecStart = "${pkgs.python3.withPackages (p: [ p.pillow ])}/bin/python3 ${./manga-import.py} ${downloads} ${library}";
      # "-": ein fehlgeschlagener Scan laesst den Import nicht als Fehler dastehen
      ExecStartPost = "-${komgaScan}";
      LoadCredential = "komga:/var/lib/secrets/komga-scan.key";
    };
  };
  systemd.timers.manga-import = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*-*-* 07:00";
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
