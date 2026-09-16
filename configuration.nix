{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./modules/software.nix
      ./modules/systemdboot.nix

      ./Hardware/hdds.nix

      ./users/lmlzr.nix

      ./containers/portainer.nix
      ./containers/firefox.nix

      ./services/jellyfin.nix
      ./services/home-assistant.nix
      ./services/karakeep.nix
      ./services/mealie.nix
      ./services/syncthing.nix
      ./services/vm-setup.nix
      ./services/docker.nix
      ./services/stirling-pdf.nix
      ./services/audiobookshelf.nix
    ];

  networking.hostName = "neotokyo"; # Define your hostname.
  # Enable networking
  networking.networkmanager.enable = true;
  # Set your time zone.
  time.timeZone = "Europe/Berlin";
  # Select internationalisation properties.
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
  # Configure console keymap
  console.keyMap = "de";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  system.stateVersion = "26.11"; 
}