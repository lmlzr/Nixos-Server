{ lib, ... }:

# Zentrale Portliste der Gameserver (Pterodactyl). Dieselben Ports leitet der VPS
# (lmlzr.com, 217.154.218.53) per WireGuard an neotokyo weiter: vps/nftables-gameforward.conf.
# Bei Aenderungen BEIDE Dateien anpassen und im Panel passende Allocations anlegen.
#
# Spiel              Port(s)                    Hinweis
# Minecraft Java     25565-25600 tcp+udp        SRV-Eintrag pro Server, udp fuer Voice-Chat-Plugins
# Minecraft Bedrock  19132-19133 udp            Geyser / Bedrock-Server
# Hytale             5520-5529 udp              QUIC
# Satisfactory       7777 tcp+udp, 8888 tcp     7777 = Standard, Adresse wird von Hand eingegeben
# ARK                7787-7790 udp              7777 belegt Satisfactory
# Don't Starve T.    10999-11010, 8766-8770 udp Shards + Steam-Auth, Master 27018/27019 (s. u.)
# CS2                27015-27020 tcp+udp        27015 = Standard (connect cs2.lmlzr.com)
# Rust               28015 udp, 28017 udp, 28082 tcp   Spiel, Query, Rust+; RCON 28016 bleibt intern
let
  r = from: to: { inherit from to; };
  p = port: r port port;
in
{
  networking.firewall = {
    allowedTCPPortRanges = [
      (r 25565 25600)
      (r 7777 7790)
      (p 8888)
      (r 27015 27020)
      (p 28082)
    ];
    allowedUDPPortRanges = [
      (r 25565 25600)
      (r 19132 19133)
      (r 5520 5529)
      (r 7777 7790)
      (r 8766 8770)
      (r 10999 11010)
      (r 27015 27020)
      (p 28015)
      (p 28017)
    ];
  };
}
