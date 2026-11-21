{ config, lib, pkgs, ... }:

# Suwayomi: Manga-Server mit den Erweiterungen von Mihon/Tachiyomi. Haelt die Manga-Bibliothek
# aktuell: Serien abonnieren, neue (und fehlende) Kapitel werden als CBZ geladen.
# Nativ aus nixpkgs, kein Container. http://10.0.0.5:4567 (nur Heimnetz, ohne Login)
#
# Ablauf: Suwayomi laedt nach /mnt/tank/media/Manga-Downloads, manga-import (taeglich) legt
# davon Hardlinks im Serienordner der Manga-Bibliothek an ("<Serie> Ch.NNN.cbz"), Komga findet
# sie beim naechsten Scan. Abweichende Serientitel in Manga-Downloads/zuordnung.json eintragen.
# Cloudflare-geschuetzte Quellen laufen ueber FlareSolverr (arr-stack).
let
  cfg = config.nas;
  port = 4567;
  dataDir = "${cfg.servicesDir}/suwayomi";
  downloads = "${cfg.mediaDir}/Manga-Downloads";
  library = "${cfg.mediaDir}/Manga";
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
    serviceConfig = {
      Type = "oneshot";
      # Hardlinks gehen nur als Besitzer der Dateien (fs.protected_hardlinks)
      User = "suwayomi";
      Group = "media";
      UMask = "0002";
      # Pillow: Manganato-Seitenstreifen wieder zusammenkleben (siehe manga-import.py)
      ExecStart = "${pkgs.python3.withPackages (p: [ p.pillow ])}/bin/python3 ${./manga-import.py} ${downloads} ${library}";
    };
  };
  systemd.timers.manga-import = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*-*-* 07:00";
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
