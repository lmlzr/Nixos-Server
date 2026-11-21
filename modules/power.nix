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

  # SATA-Link-Stromsparen fuer alle Controller (Boot-SSD, HDDs).
  # Kontrolle: cat /sys/class/scsi_host/host*/link_power_management_policy
  # Ausnahme: Boot-SSD Crucial BX500 bleibt max_performance (Kernel-Quirk nolpm, Firmware-Bug);
  # DUMMY-Ports ohne Anschluss melden "Operation not supported" - beides ist normal.
  # Wirkt derzeit auf keinem Port: Das BIOS meldet alle als Hotplug ("ext"), dafuer sperrt der
  # Kernel LPM (ebenfalls "Operation not supported"). Abhilfe: Hotplug im BIOS abschalten.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="med_power_with_dipm"
  '';

  # powertop --auto-tune stellt Runtime-PM und USB-Autosuspend auf auto. ASPM aendert es nicht.
  # Ausnahmen laufen danach: Die LAN-Karte darf nie schlafen, und das Blu-ray-Laufwerk bleibt
  # auf voller Leistung, damit ARM keine Disc-Wechsel verpasst.
  # Kontrolle: cat /sys/class/net/${config.nas.lanInterface}/device/power/control (soll "on" sein)
  powerManagement.powertop = {
    enable = true;
    postStart = ''
      echo on > /sys/class/net/${config.nas.lanInterface}/device/power/control

      if [ -e /sys/block/sr0 ]; then
        sr=$(readlink -f /sys/block/sr0)
        ata=''${sr%%/host*}
        echo on > "$ata/power/control"
        host=$(basename "$ata"/host*)
        echo max_performance > "/sys/class/scsi_host/$host/link_power_management_policy" || true
      fi
    '';
  };
}
