{ config, pkgs, ... }:

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

  # Web-UI im LAN erreichbar (wird per portMapping in den Namespace weitergeleitet).
  # Sonarr/Radarr/Lidarr erreichen qBittorrent unter 192.168.15.1:8080
  networking.firewall.allowedTCPPorts = [ webuiPort ];
}
