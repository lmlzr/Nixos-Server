{ config, lib, ... }:

let
  root = "/mnt/TB1/server/services";

  # Bind-Mounts statt Symlinks: werden erst nach dem ZFS-Mount eingehaengt und
  # vertragen sich mit systemd StateDirectory.
  # Dienste mit DynamicUser (mealie, stirling-pdf) liegen unter /var/lib/private,
  # den Besitzer setzt dort systemd selbst.
  # Nur Dienste, die auf diesem Host aktiv sind (sonst fehlen z. B. die Benutzer).
  links = lib.filterAttrs (target: link: link.enable) {
    "/var/lib/jellyfin"             = { enable = config.services.jellyfin.enable;       source = "${root}/jellyfin";       owner = "jellyfin:jellyfin"; };
    "/var/lib/audiobookshelf"       = { enable = config.services.audiobookshelf.enable; source = "${root}/audiobookshelf"; owner = "audiobookshelf:audiobookshelf"; };
    "/var/lib/private/stirling-pdf" = { enable = config.services.stirling-pdf.enable;   source = "${root}/stirling-pdf";   owner = "root:root"; };
    "/var/lib/syncthing"            = { enable = config.services.syncthing.enable;      source = "${root}/syncthing";      owner = "lmlzr:users"; };
    "/var/lib/pterodactyl-panel"    = { enable = config.services.pterodactyl.panel.enable or false; source = "${root}/pterodactyl-panel"; owner = "pterodactyl:pterodactyl"; };
    # Wings: Gameserver-Daten (volumes/, backups/, archives/)
    "/var/lib/pterodactyl"          = { enable = config.services.pterodactyl.wings.enable or false; source = "${root}/pterodactyl-wings"; owner = "root:root"; };
  };

in
{
  fileSystems = lib.mapAttrs
    (target: link: {
      device = link.source;
      fsType = "none";
      options = [ "bind" ];
      depends = [ "/mnt/TB1" ];
    })
    links;

  # systemd verlangt 0700 fuer /var/lib/private
  systemd.tmpfiles.rules = [
    "d /var/lib/private 0700 root root -"
  ];

  # Quellordner muessen vor dem Bind-Mount existieren (tmpfiles laeuft beim Boot
  # erst danach). Bestehende Ordner werden nur angelegt, wenn sie fehlen;
  # der Besitzer wird nur auf dem Ordner selbst gesetzt, nicht rekursiv.
  system.activationScripts.serviceDataDirs = {
    deps = [ "users" "groups" ];
    text = lib.concatStringsSep "\n"
      (lib.mapAttrsToList
        (target: link: ''
          mkdir -p "${link.source}"
          chown ${link.owner} "${link.source}"
        '')
        links);
  };

  # Migration: alte Symlinks (/var/lib/X -> ${root}/X) entfernen, damit die
  # Bind-Mounts eingehaengt werden koennen. Von systemd angelegte Links bleiben.
  system.activationScripts.removeOldServiceLinks.text =
    lib.concatStringsSep "\n"
      (map (name: ''
          case "$(readlink "/var/lib/${name}")" in
            ${root}/*) rm "/var/lib/${name}" ;;
          esac
        '')
        [ "jellyfin" "audiobookshelf" "stirling-pdf" "syncthing" ]);
}
