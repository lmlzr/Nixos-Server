{ config, pkgs, ... }:

{
  # Nur fuer Samba (kein Login). UID/GID wie unter TrueNAS, damit die
  # bestehenden Dateien ohne chown passen.
  users.users.dbglas = {
    isNormalUser = true;
    uid = 1003;
    group = "dbglas";
    description = "Samba-Benutzer dbglas";
    createHome = false;
    home = "/var/empty";
    shell = "${pkgs.shadow}/bin/nologin";
  };
  users.groups.dbglas.gid = 1003;
}
