{ config, pkgs, ... }:

{
  services.jellyfin = {
    enable = true;

    openFirewall = true;

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


