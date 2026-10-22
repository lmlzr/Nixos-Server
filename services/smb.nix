{ config, lib, pkgs, ... }:

# Samba-Freigaben. Passwoerter einmalig setzen:
#   sudo smbpasswd -a lmlzr
#   sudo smbpasswd -a dbglas
let
  cfg = config.nas;
in
{
  services.samba = {
    enable = true;
    openFirewall = false; # Ports nur auf dem LAN-Interface, siehe unten

    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = config.networking.hostName;
        security = "user";

        "server min protocol" = "SMB2_10";
        "map to guest" = "never";
        "restrict anonymous" = "2";

        # Nur private Netze (alle lokalen Netze), nie das Internet
        "hosts allow" = "127.0.0.1 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fd00::/8 fe80::/10";
        "hosts deny" = "ALL";

        # Jeder sieht nur die Freigaben, auf die er Zugriff hat
        "access based share enum" = "yes";

        # Keine Drucker
        "load printers" = "no";
        printing = "bsd";
        "printcap name" = "/dev/null";
        "disable spoolss" = "yes";
      };

      # Admin: gesamter share-Bereich (enthaelt lmlzr/ und dbglas/)
      share = {
        path = cfg.shareDir;
        "valid users" = "lmlzr";
        "read only" = "no";
        "create mask" = "0640";
        "directory mask" = "0750";
      };

      lmlzr = {
        path = "${cfg.shareDir}/lmlzr";
        "valid users" = "lmlzr";
        "read only" = "no";
        "create mask" = "0640";
        "directory mask" = "0750";
      };

      # dbglas sieht nur das hier; lmlzr hat als Admin ebenfalls Zugriff.
      # force user: alle Dateien gehoeren dbglas, auch wenn lmlzr sie anlegt.
      dbglas = {
        path = "${cfg.shareDir}/dbglas";
        "valid users" = "dbglas lmlzr";
        "read only" = "no";
        "force user" = "dbglas";
        "force group" = "dbglas";
        "create mask" = "0600";
        "directory mask" = "0700";
      };

      # Medien: Gruppe media darf lesen und schreiben, Dateien bleiben in Gruppe media
      media = {
        path = cfg.mediaDir;
        "valid users" = "@media";
        "read only" = "no";
        "force group" = "media";
        "create mask" = "0664";
        "directory mask" = "2775";
      };
    };
  };

  # Windows findet den Server in der Netzwerkumgebung
  services.samba-wsdd = {
    enable = true;
    interface = cfg.lanInterface;
  };

  networking.firewall.interfaces.${cfg.lanInterface} = {
    allowedTCPPorts = [ 139 445 5357 ];
    allowedUDPPorts = [ 137 138 3702 ];
  };
}
