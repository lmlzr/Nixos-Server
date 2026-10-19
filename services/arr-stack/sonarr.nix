{ config, pkgs, ... }:

{
  services.sonarr = {
    enable = true;
    openFirewall = true;
    group = "media";
    settings.server.port = 8989;
  };
}
