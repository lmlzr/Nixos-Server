{ config, pkgs, ... }:

{
  users.users.lmlzr = {
    isNormalUser = true;
    uid = 1000; # wie unter TrueNAS (Ordner psycho), damit die Dateien ohne chown passen
    description = "Leon Melzer";
    extraGroups = [ "networkmanager" "wheel" "kvm" "video" "cdrom" "media" ];
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... lme@debian"
    ];
    packages = with pkgs; [
    ];
  };
}
