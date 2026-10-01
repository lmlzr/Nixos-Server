{ config, lib, ... }:

let
  root = "/mnt/TB1/server/services";

  links = {
    "/var/lib/jellyfin"       = "${root}/jellyfin";
    "/var/lib/hass"           = "${root}/home-assistant";
    "/var/lib/audiobookshelf" = "${root}/audiobookshelf";
    "/var/lib/karakeep"       = "${root}/karakeep";
    "/var/lib/mealie"         = "${root}/mealie";
    "/var/lib/stirling-pdf"   = "${root}/stirling-pdf";
    "/var/lib/syncthing"      = "${root}/syncthing";
  };

in
{
  system.activationScripts.serviceLinks.text =
    lib.concatStringsSep "\n"
      (lib.mapAttrsToList
        (target: source: ''
          ln -sfn "${source}" "${target}"
        '')
        links);
}