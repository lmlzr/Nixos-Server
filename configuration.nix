{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./modules/software.nix
      ./modules/systemdboot.nix
      ./modules/links.nix
      ./modules/nvidia.nix
      ./modules/optimizations.nix

      #./Hardware/hdds.nix

      ./users/lmlzr.nix

      ./containers/portainer.nix
      ./containers/firefox.nix

      ./services/jellyfin.nix
      ./services/home-assistant.nix
      ./services/karakeep.nix
      ./services/mealie.nix
      ./services/syncthing.nix
      ./services/docker.nix
      ./services/stirling-pdf.nix
      ./services/audiobookshelf.nix
      ./services/lancache.nix
      ./services/smb.nix
      ./services/mosquitto.nix

      ./services/steam-lancache-prefill.nix
      ./services/arr-stack/default.nix
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
  nixpkgs.config.allowUnfree = true;
  # Secrets (WireGuard, Passwoerter) liegen ausserhalb des Nix-Stores, siehe README
  systemd.tmpfiles.rules = [ "d /etc/secrets 0711 root root -" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      # Erst auf false setzen, wenn ein Key in users/lmlzr.nix eingetragen und getestet ist
      PasswordAuthentication = true;
    };
  };
  system.stateVersion = "26.11";
}