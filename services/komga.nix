{ config, lib, pkgs, ... }:

# Komga: Manga-, Comic- und E-Book-Server mit Web-Reader, OPDS und Anbindung an Mihon
# (Android). Nativ aus nixpkgs, kein Container. http://10.0.0.5:25600
# Extern ueber nginx auf dem VPS (books.<domain>, siehe vps/), dort nur mit Komga-Login.
#
# Bibliotheken (in der Oberflaeche anlegen, Medien nur lesend):
#   Manga  /mnt/tank/media/Manga   (ein Ordner pro Serie, ein CBZ pro Kapitel mit ComicInfo.xml)
#   Comics /mnt/tank/media/Comics
#   Buecher /mnt/tank/media/Books  (Autor/Titel/Autor - Titel.epub, wie Bookshelf)
# Daten (Datenbank, Thumbnails) auf der NVMe, siehe modules/links.nix.
let
  port = 25600;
in
{
  services.komga = {
    enable = true;
    settings = {
      server.port = port;
      # Bibliotheken nicht staendig auf Aenderungen ueberwachen: weckt sonst die HDDs
      # (Scan von Hand oder nach Zeitplan in den Bibliotheks-Einstellungen)
      komga.libraries-scan-startup = false;
    };
  };

  # Medien gehoeren root:media (2775/664), Lesen reicht
  users.users.komga.extraGroups = [ "media" ];

  systemd.services.komga.unitConfig.RequiresMountsFor = [ config.nas.mediaDir ];

  networking.firewall.interfaces.${config.nas.lanInterface}.allowedTCPPorts = [ port ];
}
