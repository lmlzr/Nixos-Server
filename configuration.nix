{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./modules/software.nix
      ./modules/systemdboot.nix
      ./modules/storage-paths.nix
      ./modules/links.nix
      ./modules/nvidia.nix
      ./modules/optimizations.nix
      ./modules/mail.nix
      ./modules/shell.nix

      # NAS: ZFS-Pool tank (nur auf der echten Hardware; in der Test-VM auskommentieren)
      ./Hardware/storage.nix
      ./modules/zfs-snapshots.nix
      ./modules/storage-monitoring.nix
      ./modules/backup.nix
      ./modules/vmdocker-backup.nix
      ./modules/hdd-spindown.nix
      ./modules/power.nix

      ./users/lmlzr.nix
      ./users/dbglas.nix

      ./containers/portainer.nix
      ./containers/lancache-dashboard.nix
      ./containers/handbrake-makemkv.nix
      ./containers/arm.nix
      ./containers/bookshelf.nix
      #./containers/firefox.nix

      ./services/jellyfin.nix
      #./services/home-assistant.nix
      #./services/karakeep.nix
      #./services/mealie.nix
      #./services/syncthing.nix
      ./services/docker.nix
      ./services/stirling-pdf.nix
      ./services/audiobookshelf.nix
      ./services/lancache.nix
      ./services/smb.nix
      #./services/mosquitto.nix

      ./services/steam-lancache-prefill.nix
      ./services/iventoy.nix
      ./services/immich.nix
      ./services/arr-stack/default.nix
      ./services/seerr.nix
      ./services/pterodactyl
      ./services/gameserver-ports.nix
      ./services/checkmk-agent
      ./services/claude-rc.nix
    ];

  # Checkmk-Agent (Pull, TCP 6556), nur fuer den Checkmk-Server
  services.checkmk-agent = {
    enable = true;
    allowedFrom = [ "127.0.0.1" "::1" "10.0.0.3" ];
  };

  # Daten-HDDs nach 15 min Leerlauf abschalten (nur echte Hardware)
  nas.spindown.enable = true;

  # Automatic Ripping Machine, siehe containers/arm.nix. Vorbereitet, aus: Laufwerk noch nicht eingebaut.
  nas.arm.enable = false;

  services.pterodactyl = {
    panel.enable = true;
    # Mails (Passwort-Reset, Einladungen) ueber Proton; Token: TOKEN_PTERODACTYL
    panel.settings = {
      MAIL_MAILER = "smtp";
      MAIL_HOST = "smtp.protonmail.ch";
      MAIL_PORT = "587";
      MAIL_ENCRYPTION = "tls";
      MAIL_USERNAME = config.nas.mail.from;
      MAIL_FROM_ADDRESS = config.nas.mail.from;
    };
    panel.mailPassword.file = config.nas.mail.envFile;
    wings.enable = true;
  };

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
  nas.lanInterface = "enp4s0";
  system.stateVersion = "26.11";
}
