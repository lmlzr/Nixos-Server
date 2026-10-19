{ config, pkgs, ... }:

{
  services.radarr = {
    enable = true;
    openFirewall = true;
    group = "media";
    settings.server.port = 7878;
  };
}
