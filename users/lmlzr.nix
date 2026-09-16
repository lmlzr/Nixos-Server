{ config, pkgs, ... }:

{
  users.users.lmlzr = {
    isNormalUser = true;
    description = "Leon Melzer";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "kvm" "video" "cdrom" "sudo" ];
    packages = with pkgs; [
    ];
  };
}


