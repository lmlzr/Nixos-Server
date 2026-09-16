{ config, pkgs, ... }:

{
  users.users.server = {
    isNormalUser = true;
    description = "Server";
    extraGroups = [ "networkmanager" "libvirtd" "kvm" "video" "cdrom" ];
    packages = with pkgs; [
    ];
  };
}

