{ config, pkgs, lib, inputs, ... }:

{
    services.journald.extraConfig = "SystemMaxUse=50M";
    systemd.services.networkManager-wait-online.wantedBy = lib.mkForce [];
    #schneller builden
    nix.settings.max-jobs = "auto";
    nix.settings.cores = 0; 
    #auto delete old versions welche älter als 10 tage sind
    nix.gc = {
        automatic = true;
        options = "--delete-older-than 10d";
    };
    boot.kernelModules = [ "sg" ];
}