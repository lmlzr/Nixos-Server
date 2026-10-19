{ config, pkgs, ... }:

{
  services.jellyfin = {
    enable = true;

    openFirewall = true;

    user = "jellyfin";
    group = "jellyfin";
  };

  # NVIDIA-Hardwarebeschleunigung: siehe modules/nvidia.nix
}
