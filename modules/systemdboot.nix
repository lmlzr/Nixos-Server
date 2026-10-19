{ config, pkgs, ... }: 
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 1; # for faster boot time
  boot.kernelParams = [ "quiet" ];
}
