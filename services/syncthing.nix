{ config, pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    user = "lmlzr";
    group = "users";

    dataDir = "/home/lmlzr";

    configDir = "/home/lmlzr/.config/syncthing";

    guiAddress = "0.0.0.0:8384";

    openDefaultPorts = true;
  };
}