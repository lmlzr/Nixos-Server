{ config, pkgs, ... }:

# Trakt-Kalender als RSS fuer FreshRSS (Trakt bietet eigene Feeds nur mit VIP).
# Einrichtung und Feed-Adressen: http://10.0.0.5:8098 (nur Heimnetz, ohne Login)
#   /neu.xml   Folgen/Filme der letzten 14 Tage, /bald.xml die naechsten 30 Tage
# Trakt-API-App (Client ID/Secret) und Tokens liegen nur im State-Verzeichnis, nicht im Repo.
# Ausserdem MyAnimeList-Abgleich (malsync.py, gleiche Seite): Trakt-Anime und Komga-Manga -> MAL,
# taeglich 05:00. MAL-/Komga-Zugang ebenfalls nur im State-Verzeichnis.
# Logins laufen ueber https://news.<DOMAIN>/trakt-callback (VPS leitet per 302 hierher weiter).
let
  cfg = config.nas;
  port = 8098;
  src = pkgs.runCommand "trakt-rss" { } ''
    mkdir $out
    cp ${./trakt-rss.py} $out/trakt-rss.py
    cp ${./malsync.py} $out/malsync.py
  '';
in
{
  systemd.services.trakt-rss = {
    description = "Trakt-Kalender als RSS-Feed";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${src}/trakt-rss.py ${toString port} /var/lib/trakt-rss https://news.${cfg.private.DOMAIN}/trakt-callback";
      DynamicUser = true;
      StateDirectory = "trakt-rss";
      StateDirectoryMode = "0700";
      Restart = "on-failure";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  # FreshRSS blockt Feeds aus dem eigenen Netz, diesen hier erlauben
  services.freshrss.internalHostAllowlist = [ "10.0.0.5:${toString port}" ];

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
