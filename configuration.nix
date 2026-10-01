{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./modules/software.nix
      ./modules/systemdboot.nix
      ./modules/links.nix

      ./Hardware/hdds.nix

      ./users/lmlzr.nix

      ./containers/portainer.nix
      ./containers/firefox.nix

      ./services/jellyfin.nix
      ./services/home-assistant.nix
      ./services/karakeep.nix
      ./services/mealie.nix
      ./services/syncthing.nix
      # ./services/vm-setup.nix # dont need it my router is a vm host
      ./services/docker.nix
      ./services/stirling-pdf.nix
      ./services/audiobookshelf.nix
      ./services/lancache.nix 
    ];

  networking.hostName = "neotokyo";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "de_DE.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };
  console.keyMap = "de";
  security.rtkit.enable = true;
  nixpkgs.config.allowUnfree = true;
  services.openssh.enable = true;
  system.stateVersion = "26.11";
}