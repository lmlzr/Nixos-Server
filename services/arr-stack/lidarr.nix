{ config, pkgs, ... }:

{
  services.lidarr = {
    enable = true;
    openFirewall = true;
    group = "media";
    settings.server.port = 8686;
  };
}
