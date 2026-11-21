{ config, pkgs, ... }:
{
  # Headless: nur Treiber + NVENC/NVDEC fuer Jellyfin-Transcoding, kein X-Server-Tuning
  nixpkgs.config.nvidia.acceptLicense = true;
  services.xserver.videoDrivers = [ "nvidia" ]; # laedt den Treiber, startet keinen X-Server

  hardware = {
    nvidia = {
      modesetting.enable = true;
      # Quadro P400 (Pascal): ab Treiber 590 nicht mehr unterstuetzt, daher 580er-Legacy-Zweig.
      # postFixup: nvidia-smi u. a. stuerzen sonst in ld-linux ab (SIGSEGV), siehe nvidia-fix-elf.py
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          ${pkgs.python3}/bin/python3 ${./nvidia-fix-elf.py} $bin/bin/*
        '';
      });
      nvidiaSettings = false;
      open = false;
      # Treiber dauerhaft geladen: GPU bleibt im Stromsparzustand P8, Transcodes starten schneller
      nvidiaPersistenced = true;
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
