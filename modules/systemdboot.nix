{ config, pkgs, ... }: 
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 1; # for faster boot time
  boot.kernelParams = [ "quiet" ];


  systemd.services.set-gpu-irq = {
    description = "Set GPU IRQ Affinity";
    wantedBy = [ "multi-user.target" ];
    after = [ "sysinit.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''/bin/sh -c "echo 10 > /proc/irq/112/smp_affinity"'';
    };
  };
}