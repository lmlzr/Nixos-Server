{ config, pkgs, ... }:

{
  # Virtualisierung
  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # Weboberfläche zur VM-Steuerung
  services.cockpit = {
    enable = true;
    port = 9090;
    openFirewall = true;
  };

  security.pam.services.cockpit = {};

  environment.systemPackages = with pkgs; [
    qemu_kvm
    libvirt
  ];

  # Benutzer darf libvirt verwalten
  users.users.lmlzr.extraGroups = [
    "libvirtd"
  ];

  networking.firewall.allowedTCPPorts = [
    9090
  ];
}