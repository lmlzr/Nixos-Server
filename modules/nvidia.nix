{ config, pkgs, ... }:
{
  # Headless: nur Treiber + NVENC/NVDEC fuer Jellyfin-Transcoding, kein X-Server-Tuning
  nixpkgs.config.nvidia.acceptLicense = true;
  services.xserver.videoDrivers = [ "nvidia" ]; # laedt den Treiber, startet keinen X-Server

  hardware = {
    nvidia = {
      modesetting.enable = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;
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
