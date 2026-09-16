{ config, pkgs, ... }:
{
# Kernel
  boot.kernelPackages = pkgs.linuxPackages_hardened;

  boot.kernelParams = [ 
    # example settings
    "quiet"
    # example kernel module parameter
    "usbcore.blinkenlights=1"

    "scsi_mod.use_blk_mq=1"
    "dm_mod.use_blk_mq=Y"
    "mitigations=off"
    "zswap.enabled=1"
    "iommu=pt"
    "systemd.unified_cgroup_hierarchy=0"
  ];


  boot.kernel.sysctl = {
    "vm.dirty_ratio" = 15;
    "vm.dirty_background_ratio" = 5;
    "kernel.sched_autogroup_enabled" = 0;
    "kernel.sched_min_granularity_ns" = 10000000;
    "kernel.sched_wakeup_granularity_ns" = 15000000;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.ip_forward" = 1;
  };



}