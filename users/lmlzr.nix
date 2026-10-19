{ config, pkgs, ... }:

{
  users.users.lmlzr = {
    isNormalUser = true;
    description = "Leon Melzer";
    extraGroups = [ "networkmanager" "wheel" "kvm" "video" "cdrom" ];
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... lme@debian"
    ];
    packages = with pkgs; [
    ];
  };
}
