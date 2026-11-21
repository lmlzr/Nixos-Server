{ config, lib, ... }:

# Lokaler HTTPS-Proxy fuer die oeffentlichen Namen (<name>.<DOMAIN>), damit Geraete im Heimnetz
# nicht ueber den VPS gehen. Pi-hole (vmdocker) loest die Namen im LAN auf ${ip} auf, von aussen
# zeigen sie weiter auf den VPS (vps/nginx-*.conf, gleiche Ziele wie hier).
#
# Eigene IP ${ip}, weil 10.0.0.5:443 der LANCache belegt (SNI-Weiterleitung, services/lancache.nix).
# Zertifikat: Wildcard *.<DOMAIN> von Let's Encrypt per DNS-01 ueber die Cloudflare-API (Port 80/443
# muss dafuer nicht von aussen erreichbar sein). Bis es da ist, nimmt nginx ein selbstsigniertes.
#
# Einrichten (einmalig): in Cloudflare unter My Profile > API Tokens ein Token mit
# "Zone / DNS / Edit" nur fuer die Domain anlegen, dann
#   sudo install -d -m 700 /var/lib/acme-secrets
#   sudo sh -c 'echo CF_DNS_API_TOKEN=<token> > /var/lib/acme-secrets/cloudflare.env'
#   sudo chmod 600 /var/lib/acme-secrets/cloudflare.env
#   sudo systemctl start acme-order-renew-local.service   (oder nrs)
#
# Neuer Dienst: unten in "hosts" eintragen und in Pi-hole (Local DNS Records) <name>.<DOMAIN> -> ${ip}.
let
  ip = "10.0.0.6";
  domain = config.nas.private.DOMAIN;

  proxyHeaders = ''
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 1h;
    proxy_send_timeout 1h;
  '';
  noBuffer = ''
    proxy_buffering off;
    proxy_request_buffering off;
  '';

  # name -> { to, body ? "1m", extra ? "", locations ? {} }  (wie vps/nginx-*.conf)
  hosts = {
    homeassist = { to = "http://10.0.0.3:8123"; };
    audiobooks = { to = "http://10.0.0.5:13378"; body = "0"; extra = "proxy_buffering off;"; };
    mealie = { to = "http://10.0.0.3:9925"; body = "50m"; };
    push = { to = "http://10.0.0.3:6969"; body = "20m"; extra = noBuffer; };
    router = { to = "https://10.0.0.2:8006"; body = "0"; extra = "proxy_ssl_verify off;\n" + noBuffer; };
    pdf = { to = "http://10.0.0.5:8083"; body = "2g"; };
    nutritrace = { to = "http://10.0.0.3:3001"; };
    karakeep = { to = "http://10.0.0.3:8084"; body = "50m"; };
    check = {
      to = "http://10.0.0.3:8081";
      locations."= /".return = "302 /cmk/check_mk/";
    };
    seerr = { to = "http://10.0.0.5:5055"; };
    files = { to = "http://10.0.0.5:8088"; body = "0"; extra = noBuffer; };
    books = {
      to = "http://10.0.0.5:25600";
      body = "0";
      extra = "proxy_buffering off;";
      # OPDS-Downloads ohne Content-Disposition (siehe vps/nginx-books.conf)
      locations."~ ^/opds/v[0-9.]+/books/[^/]+/file/".extraConfig = ''
        proxy_pass http://10.0.0.5:25600;
        ${proxyHeaders}
        proxy_buffering off;
        proxy_hide_header Content-Disposition;
      '';
    };
    news = {
      to = "http://10.0.0.5:8097";
      locations."= /trakt-callback".return = "302 http://10.0.0.5:8098/callback$is_args$args";
    };
    musicassistant = { to = "http://10.0.0.3:8095"; extra = "proxy_buffering off;"; };
    # nur auf dem VPS eingerichtet (nicht in vps/), Ziele von dort uebernommen
    jellyfin = { to = "http://10.0.0.5:8096"; body = "20G"; extra = "proxy_buffering off;"; };
    immich = { to = "http://10.0.0.5:2283"; body = "50000M"; extra = noBuffer; };
    # Nur ueber den VPS: firefox (Basic Auth dort, im LAN http://10.0.0.3:8031), hosting und
    # wings (Panel-Node hat Daemon-Port 8443, lokal antwortet dort Wings ohne TLS)
  };

  vhost = name: h: {
    serverName = "${name}.${domain}";
    listenAddresses = [ ip ];
    onlySSL = true;
    useACMEHost = "local";
    extraConfig = "client_max_body_size ${h.body or "1m"};";
    locations = {
      "/".extraConfig = ''
        proxy_pass ${h.to};
        ${proxyHeaders}
        ${h.extra or ""}
      '';
    } // (h.locations or { });
  };
in
{
  networking.interfaces.${config.nas.lanInterface}.ipv4.addresses = [
    { address = ip; prefixLength = 24; }
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = config.nas.private.MAIL_ALERT_TO;
    certs.local = {
      domain = "*.${domain}";
      dnsProvider = "cloudflare";
      # Pi-hole kennt die Namen lokal, fuer die Pruefung der TXT-Records direkt fragen
      dnsResolver = "1.1.1.1:53";
      environmentFile = "/var/lib/acme-secrets/cloudflare.env";
      group = config.services.nginx.group;
      reloadServices = [ "nginx" ];
    };
  };

  services.nginx.virtualHosts = lib.mapAttrs' (name: h: lib.nameValuePair "lan-${name}" (vhost name h)) hosts // {
    # Unbekannte Namen und http auf der Proxy-IP
    lan-default = {
      serverName = "_";
      default = true;
      listenAddresses = [ ip ];
      addSSL = true;
      useACMEHost = "local";
      locations."/".extraConfig = ''
        if ($scheme = http) { return 301 https://$host$request_uri; }
        return 444;
      '';
    };
  };
}
