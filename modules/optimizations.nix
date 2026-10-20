{ config, pkgs, lib, inputs, ... }:

{
    services.journald.settings.Journal.SystemMaxUse = "50M";
    systemd.services.NetworkManager-wait-online.enable = false;
    #schneller builden
    nix.settings.max-jobs = "auto";
    nix.settings.cores = 0; 
    #auto delete old versions welche älter als 10 tage sind
    nix.gc = {
        automatic = true;
        options = "--delete-older-than 10d";
    };
    #doppelte dateien im store per hardlink zusammenlegen
    nix.settings.auto-optimise-store = true;
    #wenn beim builden weniger als 5 GiB frei sind, automatisch aufraeumen bis 20 GiB frei
    nix.settings.min-free = 5 * 1024 * 1024 * 1024;
    nix.settings.max-free = 20 * 1024 * 1024 * 1024;
    boot.kernelModules = [ "sg" ];
}