{ config, pkgs, ... }:

{
  # Umgeht Cloudflare-Schutz fuer Indexer in Prowlarr.
  # Nur lokal genutzt (Prowlarr laeuft auf demselben Host) -> kein Port nach aussen.
  # In Prowlarr: Settings -> Indexers -> FlareSolverr, Host http://127.0.0.1:8191
  services.flaresolverr = {
    enable = true;
    port = 8191;
    openFirewall = false;
  };
}
