{ config, lib, ... }:

let
  root = config.nas.servicesDir;

  # Bind-Mounts statt Symlinks: werden erst nach dem ZFS-Mount eingehaengt und
  # vertragen sich mit systemd StateDirectory.
  # Dienste mit DynamicUser (stirling-pdf, prowlarr) liegen unter /var/lib/private,
  # den Besitzer setzt dort systemd selbst.
  # Nur Dienste, die auf diesem Host aktiv sind (sonst fehlen z. B. die Benutzer).
  # service = systemd-Unit, die ohne den Mount nicht starten darf.
  links = lib.filterAttrs (target: link: link.enable) {
    "/var/lib/jellyfin"             = { enable = config.services.jellyfin.enable;       service = "jellyfin";       source = "${root}/jellyfin";       owner = "jellyfin:jellyfin"; };
    "/var/lib/audiobookshelf"       = { enable = config.services.audiobookshelf.enable; service = "audiobookshelf"; source = "${root}/audiobookshelf"; owner = "audiobookshelf:audiobookshelf"; };
    "/var/lib/private/stirling-pdf" = { enable = config.services.stirling-pdf.enable;   service = "stirling-pdf";   source = "${root}/stirling-pdf";   owner = "root:root"; };
    "/var/lib/syncthing"            = { enable = config.services.syncthing.enable;      service = "syncthing";      source = "${root}/syncthing";      owner = "lmlzr:users"; };
    "/var/lib/sonarr"               = { enable = config.services.sonarr.enable;         service = "sonarr";         source = "${root}/sonarr";         owner = "sonarr:media"; };
    "/var/lib/radarr"               = { enable = config.services.radarr.enable;         service = "radarr";         source = "${root}/radarr";         owner = "radarr:media"; };
    "/var/lib/lidarr"               = { enable = config.services.lidarr.enable;         service = "lidarr";         source = "${root}/lidarr";         owner = "lidarr:media"; };
    "/var/lib/private/prowlarr"     = { enable = config.services.prowlarr.enable;       service = "prowlarr";       source = "${root}/prowlarr";       owner = "root:root"; };
    "/var/lib/qBittorrent"          = { enable = config.services.qbittorrent.enable;    service = "qbittorrent";    source = "${root}/qbittorrent";    owner = "qbittorrent:media"; };
    # MariaDB (Datenbank des Pterodactyl-Panels)
    "/var/lib/mysql"                = { enable = config.services.mysql.enable;          service = "mysql";          source = "${root}/mysql";          owner = "mysql:mysql"; };
    "/var/lib/pterodactyl-panel"    = { enable = config.services.pterodactyl.panel.enable or false; service = "pterodactyl-panel-setup"; source = "${root}/pterodactyl-panel"; owner = "pterodactyl:pterodactyl"; };
    # Portainer (Docker-Container, Unit heisst docker-portainer)
    "/var/lib/portainer"            = { enable = config.virtualisation.oci-containers.containers ? portainer; service = "docker-portainer"; source = "${root}/portainer"; owner = "root:root"; };
    # Wings: Gameserver-Daten (volumes/, backups/, archives/)
    "/var/lib/pterodactyl"          = { enable = config.services.pterodactyl.wings.enable or false; service = "wings"; source = "${root}/pterodactyl-wings"; owner = "root:root"; };
  };

in
{
  nas.mounts = lib.mapAttrs
    (target: link: {
      device = link.source;
      fsType = "none";
      # Quellordner wird vorher von nas-service-dirs angelegt
      options = [ "bind" "nofail" "x-systemd.requires=nas-service-dirs.service" ];
      depends = [ root ];
    })
    links;

  systemd.services = lib.mapAttrs' (target: link:
    # Dienst startet nur, wenn sein Datenordner wirklich eingehaengt ist
    lib.nameValuePair link.service { unitConfig.RequiresMountsFor = [ target ]; }
  ) links // {
    # Quellordner muessen vor dem Bind-Mount existieren. Laeuft bei jedem Boot nach
    # dem Einhaengen des Pools (tmpfiles waere zu spaet, Aktivierung zu frueh).
    # Fehlende Ordner werden angelegt; der Besitzer wird nur auf dem Ordner selbst
    # gesetzt, nicht rekursiv.
    nas-service-dirs = {
      description = "NAS: Datenordner der Dienste anlegen";
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = [ root ];
      };
      before = [ "local-fs.target" "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatStringsSep "\n" (lib.mapAttrsToList (target: link: ''
        mkdir -p "${link.source}"
        chown ${link.owner} "${link.source}"
      '') links);
    };
  };

  # systemd verlangt 0700 fuer /var/lib/private
  systemd.tmpfiles.rules = [
    "d /var/lib/private 0700 root root -"
  ];

  # Migration: alte Symlinks (/var/lib/X -> /mnt/...) entfernen, damit die
  # Bind-Mounts eingehaengt werden koennen. Von systemd angelegte Links bleiben.
  system.activationScripts.removeOldServiceLinks.text =
    lib.concatStringsSep "\n"
      (map (name: ''
          case "$(readlink "/var/lib/${name}")" in
            /mnt/*) rm "/var/lib/${name}" ;;
          esac
        '')
        [ "jellyfin" "audiobookshelf" "stirling-pdf" "syncthing" ]);
}
