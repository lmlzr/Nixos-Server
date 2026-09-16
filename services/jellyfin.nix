{ config, pkgs, ... }:

{
  services.jellyfin = {
    enable = true;

    openFirewall = true;

    dataDir = "/mnt/tb1/server/services/jellyfin";

    cacheDir = "/var/cache/jellyfin";

    user = "jellyfin";
    group = "jellyfin";
  };

  # NVIDIA-Hardwarebeschleunigung
  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    jellyfin
    jellyfin-web
  ];
}


