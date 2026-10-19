{ config, lib, ... }:

let
  root = "/mnt/TB1/server/services";

  # Bind-Mounts statt Symlinks: werden erst nach dem ZFS-Mount eingehaengt und
  # vertragen sich mit systemd StateDirectory.
  # Dienste mit DynamicUser (mealie, stirling-pdf) liegen unter /var/lib/private.
  links = {
    "/var/lib/jellyfin"             = "${root}/jellyfin";
    "/var/lib/hass"                 = "${root}/home-assistant";
    "/var/lib/audiobookshelf"       = "${root}/audiobookshelf";
    "/var/lib/karakeep"             = "${root}/karakeep";
    "/var/lib/private/mealie"       = "${root}/mealie";
    "/var/lib/private/stirling-pdf" = "${root}/stirling-pdf";
    "/var/lib/syncthing"            = "${root}/syncthing";
  };

in
{
  fileSystems = lib.mapAttrs
    (target: source: {
      device = source;
      fsType = "none";
      options = [ "bind" ];
      depends = [ "/mnt/TB1" ];
    })
    links;

  # systemd verlangt 0700 fuer /var/lib/private
  systemd.tmpfiles.rules = [
    "d /var/lib/private 0700 root root -"
  ];

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
