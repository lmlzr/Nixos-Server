{ config, pkgs, ... }:
{
  # Headless: nur Treiber + NVENC/NVDEC fuer Jellyfin-Transcoding, kein X-Server-Tuning
  nixpkgs.config.nvidia.acceptLicense = true;
  services.xserver.videoDrivers = [ "nvidia" ]; # laedt den Treiber, startet keinen X-Server

  hardware = {
    nvidia = {
      modesetting.enable = true;
      # Quadro P400 (Pascal): ab Treiber 590 nicht mehr unterstuetzt, daher 580er-Legacy-Zweig
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
      nvidiaSettings = false;
      open = false;
    };
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
      ];
    };
  };

  users.users.jellyfin.extraGroups = [ "video" "render" ];
}
