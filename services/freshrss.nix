{ config, lib, pkgs, ... }:

# FreshRSS: werbefreier News-Sammler fuer RSS-Feeds; Seiten ohne Feed per "HTML + XPath"
# (Web Scraping) direkt in FreshRSS. Nativ aus nixpkgs (PHP-FPM + nginx), kein Container.
# Heimnetz: http://10.0.0.5:8097, extern https://news.<DOMAIN> ueber nginx auf dem VPS
# (vps/nginx-news.conf). Apps (Read You, Capy Reader, FeedMe, ...) ueber die Google-Reader-API:
# Server https://news.<DOMAIN>/api/greader.php, Benutzer admin, API-Passwort im FreshRSS-Profil.
# Login-Passwort fuer "admin": beim ersten Start zufaellig erzeugt in ${passFile}
# (lesbar fuer die Gruppe media), aendern = Datei bearbeiten + freshrss-config neu starten.
let
  cfg = config.nas;
  port = 8097;
  passFile = "/var/lib/freshrss-admin-passwort";
in
{
  services.freshrss = {
    enable = true;
    baseUrl = "https://news.${cfg.private.DOMAIN}";
    defaultUser = "admin";
    passwordFile = passFile;
    language = "de";
    api.enable = true;
    virtualHost = "freshrss";
  };

  # Eigener Port: Port 80 gehoert dem LANCache-nginx
  services.nginx.virtualHosts.freshrss.listen = [ { addr = "0.0.0.0"; inherit port; } ];

  # Admin-Passwort einmalig erzeugen, bevor FreshRSS eingerichtet wird
  systemd.services.freshrss-config.serviceConfig.ExecStartPre = "+" + pkgs.writeShellScript "freshrss-passwort" ''
    if [ ! -s ${passFile} ]; then
      ${pkgs.openssl}/bin/openssl rand -base64 18 | tr -d '/+=' > ${passFile}
    fi
    chown freshrss:media ${passFile}
    chmod 0440 ${passFile}
  '';

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
