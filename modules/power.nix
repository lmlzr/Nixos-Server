{ config, lib, ... }:

# Stromsparen im Leerlauf (Ryzen 5 3600, kein Desktop). Messbar nur mit Steckdosen-Messgeraet.
# PCIe-ASPM bewusst noch nicht: kann bei der Realtek-2,5G-Karte Aussetzer machen, separat testen.
{
  # CPU (amd-pstate-epp, Governor powersave): weniger Hochtakten bei leichter Last.
  # Volle Leistung bleibt verfuegbar; Jellyfin transkodiert ohnehin ueber die GPU.
  # Kontrolle: cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
  systemd.tmpfiles.rules = [
    "w /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference - - - - balance_power"
  ];

  # SATA-Link-Stromsparen fuer alle Controller (Boot-SSD, L2ARC-SSD, HDDs).
  # Kontrolle: cat /sys/class/scsi_host/host*/link_power_management_policy
  # Ausnahme: Boot-SSD Crucial BX500 bleibt max_performance (Kernel-Quirk nolpm, Firmware-Bug);
  # DUMMY-Ports ohne Anschluss melden "Operation not supported" - beides ist normal.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="med_power_with_dipm"
  '';
}
