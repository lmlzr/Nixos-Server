{ config, lib, ... }:

let
  root = "/mnt/TB1/server/services";

  # Bind-Mounts statt Symlinks: werden erst nach dem ZFS-Mount eingehaengt und
  # vertragen sich mit systemd StateDirectory.
  # Dienste mit DynamicUser (mealie, stirling-pdf) liegen unter /var/lib/private,
  # den Besitzer setzt dort systemd selbst.
  links = {
    "/var/lib/jellyfin"             = { source = "${root}/jellyfin";       owner = "jellyfin:jellyfin"; };
    "/var/lib/hass"                 = { source = "${root}/home-assistant"; owner = "hass:hass"; };
    "/var/lib/audiobookshelf"       = { source = "${root}/audiobookshelf"; owner = "audiobookshelf:audiobookshelf"; };
    "/var/lib/karakeep"             = { source = "${root}/karakeep";       owner = "karakeep:karakeep"; };
    "/var/lib/private/mealie"       = { source = "${root}/mealie";         owner = "root:root"; };
    "/var/lib/private/stirling-pdf" = { source = "${root}/stirling-pdf";   owner = "root:root"; };
    "/var/lib/syncthing"            = { source = "${root}/syncthing";      owner = "lmlzr:users"; };
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
        [ "jellyfin" "hass" "audiobookshelf" "karakeep" "mealie" "stirling-pdf" "syncthing" ]);
}
