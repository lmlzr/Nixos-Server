{ config, pkgs, ... }:
{
  boot.supportedFilesystems = [ "zfs" ];

  networking.hostId = "99f03424";

  boot.zfs.extraPools = [
    "TB1"
  ];

  environment.systemPackages = with pkgs; [
    zfs
    smartmontools
  ];

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };

  services.smartd.enable = true;
}