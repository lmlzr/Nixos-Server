{ config, pkgs, ... }:

{
  # Seerr (frueher Jellyseerr): Film-/Serienwuensche, leitet an Sonarr/Radarr weiter
  services.seerr = {
    enable = true;
    port = 5055;
    openFirewall = true;
  };
}
