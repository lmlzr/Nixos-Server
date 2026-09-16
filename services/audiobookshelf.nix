{ config, pkgs, ... }:

{
  services.audiobookshelf = {
    enable = true;
    port = 13378;
    host = "0.0.0.0";
    openFirewall = true;
  };
}