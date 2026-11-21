{ config, lib, pkgs, ... }:

let
  webuiPort = 8080;
  fast = config.nas.fastPool;
  incompleteDir = "/mnt/${fast}/incomplete";

  # Dienst fuer qbt-seed.sh (siehe Timer unten), laeuft im VPN-Namespace: dort gilt
  # 127.0.0.1 als localhost und qBittorrent verlangt keinen Login.
  qbtSeed = action: what: {
    description = "qBittorrent: Seeden ${what}";
    after = [ "qbittorrent.service" ];
    vpnConfinement = {
      enable = true;
      vpnNamespace = "proton";
    };
    path = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${./qbt-seed.sh} ${action} http://127.0.0.1:${toString webuiPort}";
    };
  };
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
      "10.10.0.0/24"     # WireGuard ueber den VPS (Handy, Absender 10.10.0.1), vps/setup-phone-vpn.sh
      "192.168.122.0/24" # libvirt-Netz der Test-VM
    ];
    portMappings = [
      { from = webuiPort; to = webuiPort; }
    ];
  };

  # proton-up pingt den VPN-Server nur 20 s lang und bricht dann ab. Nach einem Stromausfall
  # startet der Router mit und antwortet erst spaeter auf DHCP, ohne Retry bliebe das VPN aus.
  systemd.services.proton = {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Waechter: Nach einem Neustart von OPNsense (2026-11-03) kam der Tunnel nicht von selbst
  # zurueck, "latest handshake" blieb stehen, bis proton neu gestartet wurde. WireGuard erneuert
  # den Handshake mit Keepalive alle ~2 min; ist der letzte aelter als 5 min und die normale
  # Leitung geht, wird proton (samt qBittorrent, SABnzbd, Port-Forwarding) neu gestartet.
  # Kontrolle: journalctl -u proton-watchdog
  systemd.services.proton-watchdog = {
    description = "ProtonVPN-Tunnel pruefen und bei Bedarf neu starten";
    after = [ "proton.service" ];
    path = [ pkgs.iproute2 pkgs.wireguard-tools pkgs.iputils pkgs.coreutils pkgs.systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      systemctl -q is-active proton.service || exit 0
      last=$(ip netns exec proton wg show proton0 latest-handshakes | cut -f2 | sort -n | tail -1)
      age=$(( $(date +%s) - ''${last:-0} ))
      [ "$age" -le 300 ] && exit 0
      # Ohne Internet hilft ein Neustart nicht, dann nur warten
      if ! ping -c1 -W3 1.1.1.1 >/dev/null && ! ping -c1 -W3 9.9.9.9 >/dev/null; then
        echo "Letzter Handshake vor $age s, aber kein Internet, warte"; exit 0
      fi
      echo "Letzter Handshake vor $age s, starte proton neu"
      systemctl restart proton.service
    '';
  };
  systemd.timers.proton-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "2min";
    };
  };

  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "proton";
  };
  # Schlaegt der erste proton-Start fehl, verwirft systemd den Start der BindsTo-Dienste
  # ("dependency") und holt ihn beim Retry nicht nach. wantedBy startet sie mit jedem
  # erfolgreichen proton-Start, auch nach einem manuellen Neustart. Gilt auch fuer sabnzbd
  # und proton-portforward.
  systemd.services.qbittorrent.wantedBy = [ "proton.service" ];

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
  # Eigenes Dataset ausserhalb von fast/services: keine Snapshots, kein syncoid (Snapshots hielten
  # fertig verschobene Torrents wochenlang auf der NVMe fest). Die Quota schuetzt die Dienste
  # davor, dass Torrents den Pool fuellen. Einmalig anlegen, vor dem ersten Rebuild:
  #   sudo zfs create -o mountpoint=legacy -o quota=600G fast/incomplete
  # Der alte Ordner bleibt, bis er leer ist und TempPath umgestellt wurde (README "qBittorrent").
  nas.mounts = lib.mkIf (fast != null) {
    ${incompleteDir} = {
      device = "${fast}/incomplete";
      fsType = "zfs";
      options = [ "nofail" ];
    };
  };
  systemd.tmpfiles.rules = [
    "d ${config.nas.servicesDir}/qbittorrent/incomplete 2775 qbittorrent media -"
  ] ++ lib.optional (fast != null) "d ${incompleteDir} 2775 qbittorrent media -";
  systemd.services.qbittorrent.unitConfig.RequiresMountsFor =
    [ config.nas.servicesDir ] ++ lib.optional (fast != null) incompleteDir;
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
    wantedBy = [ "multi-user.target" "proton.service" ];
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

  # Nachts nicht seeden, damit die HDDs in den Spindown koennen: 21-8 Uhr werden fertige
  # Torrents alle 15 min gestoppt (auch die, die nachts fertig werden), um 8 Uhr wieder gestartet.
  # Downloads laufen weiter, sie liegen auf der NVMe. Logik in qbt-seed.sh (Tag "seedpause"),
  # dasselbe Skript nutzt Home Assistant fuer die Buttons. Von Hand:
  #   sudo systemctl start qbt-seed-stop   bzw.   qbt-seed-start
  systemd.services.qbt-seed-stop = qbtSeed "stop" "pausieren";
  systemd.services.qbt-seed-start = qbtSeed "start" "fortsetzen";

  systemd.timers.qbt-seed-stop = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*-*-* 21..23,00..07:00/15:00";
  };
  systemd.timers.qbt-seed-start = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 08:00:00";
      Persistent = true; # war der Server um 8 Uhr aus, beim naechsten Start nachholen
    };
  };
}
