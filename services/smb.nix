{ config, pkgs, ... }:

{
  services.samba = {
    enable = true;
    openFirewall = true;

    settings = {
      global = {
        workgroup = "WORKGROUP";
        security = "user";
      };

      share = {
        path = "/mnt/TB1";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "lmlzr";
      };
    };
  };
}

