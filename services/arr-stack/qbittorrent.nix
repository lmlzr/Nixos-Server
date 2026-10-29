{ config, lib, pkgs, ... }:

let
  webuiPort = 8080;
in
{
  # qBittorrent laeuft in einem eigenen Network-Namespace, dessen gesamter
  # Traffic durch WireGuard (ProtonVPN) geht. Faellt das VPN weg, hat
  # qBittorrent kein Netz – kein Leak ueber die normale Leitung.
  #
  # WireGuard-Config von ProtonVPN (Downloads -> WireGuard) ablegen unter:
  #   /etc/secrets/proton-wg.conf  (root:root, 0600)
  vpnNamespaces.proton = {
    enable = true;
    wireguardConfigFile = "/etc/secrets/proton-wg.conf";
    # Netze, aus denen die Web-UI erreichbar ist. Nicht zu weit fassen:
    # 10.0.0.0/8 wuerde z.B. ProtonVPNs 10.2.0.x (Tunnel/DNS) am VPN vorbei leiten.
    accessibleFrom = [
      "10.0.0.0/24"      # Heimnetz
      "192.168.122.0/24" # libvirt-Netz der Test-VM
    ];
    portMappings = [
      { from = webuiPort; to = webuiPort; }
    ];
  };

  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "proton";
  };

  services.qbittorrent = {
    enable = true; # nutzt qbittorrent-nox (ohne GUI)
    group = "media";
    inherit webuiPort;
    # Torrent-Port nur im VPN relevant; ProtonVPN vergibt den Forwarding-Port dynamisch
    openFirewall = false;
  };

  # Unfertige Torrents auf der NVMe (qBittorrent: "Unvollstaendige Torrents speichern in"),
  # erst der fertige Download wird nach tank/media verschoben. Sonst schreibt jeder laufende
  # Download staendig auf die HDDs und sie gehen nie in den Spindown.
  systemd.tmpfiles.rules = [
    "d ${config.nas.servicesDir}/qbittorrent/incomplete 2775 qbittorrent media -"
  ];
  systemd.services.qbittorrent.unitConfig.RequiresMountsFor = [ config.nas.servicesDir ];
  # Dateien gruppen-beschreibbar (media) anlegen: Sonarr/Radarr duerfen sonst wegen
  # fs.protected_hardlinks keinen Hardlink setzen und kopieren still (doppelter Platz).
  systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";

  # Web-UI im LAN erreichbar (wird per portMapping in den Namespace weitergeleitet).
  # Sonarr/Radarr/Lidarr erreichen qBittorrent unter 192.168.15.1:8080
  networking.firewall.allowedTCPPorts = [ webuiPort ];

  # ProtonVPN-Port-Forwarding (NAT-PMP): ohne weitergeleiteten Port kann kein Peer
  # qBittorrent erreichen, seltene Torrents bleiben dann "stalled". Proton vergibt den Port
  # nur, solange er alle < 60 s erneuert wird, und er kann wechseln; deshalb laeuft das hier
  # dauerhaft im VPN-Namespace und traegt den Port in qBittorrent ein.
  # Voraussetzungen: WireGuard-Config fuer einen P2P-Server mit "NAT-PMP" erzeugt, und in
  # qBittorrent (Optionen -> WebUI) "Authentifizierung fuer Clients auf localhost umgehen" an.
  # Kontrolle: journalctl -u proton-portforward
  systemd.services.proton-portforward = {
    description = "ProtonVPN Port-Forwarding fuer qBittorrent";
    after = [ "qbittorrent.service" ];
    wants = [ "qbittorrent.service" ];
    wantedBy = [ "multi-user.target" ];
    vpnConfinement = {
      enable = true;
      vpnNamespace = "proton";
    };
    path = [ pkgs.libnatpmp pkgs.curl pkgs.gnused ];
    script = ''
      gw=10.2.0.1
      api=http://127.0.0.1:${toString webuiPort}/api/v2/app
      current=
      tries=0
      while true; do
        out=$(natpmpc -a 1 0 udp 60 -g $gw && natpmpc -a 1 0 tcp 60 -g $gw) || {
          echo "NAT-PMP-Anfrage fehlgeschlagen (P2P-Server mit NAT-PMP?)"; sleep 15; continue; }
        port=$(echo "$out" | sed -n 's/.*Mapped public port \([0-9]*\) protocol TCP.*/\1/p')
        if [ -n "$port" ] && [ "$port" != "$current" ]; then
          if curl -sf --data "json={\"listen_port\":$port,\"random_port\":false,\"upnp\":false}" \
               "$api/setPreferences"; then
            echo "qBittorrent lauscht jetzt auf Port $port"; current=$port
          elif [ $((tries += 1)) -ge 6 ]; then
            # direkt nach einem qBittorrent-Start ist die Web-UI noch nicht bereit
            echo "Port $port konnte nicht gesetzt werden (localhost-Bypass in qBittorrent an?)"
            tries=0
          else
            sleep 5; continue
          fi
        fi
        sleep 45
      done
    '';
    serviceConfig = {
      Restart = "always";
      RestartSec = "10s";
    };
  };
}
