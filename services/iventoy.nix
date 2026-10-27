{ config, lib, pkgs, ... }:

# iVentoy: Netzwerk-Boot (PXE) direkt aus ISO-Dateien, BIOS und UEFI.
# ISOs einfach nach /mnt/tank/media/ISOs legen (SMB-Freigabe "media" oder qBittorrent-Kategorie "ISOs").
# Weboberflaeche: http://10.0.0.5:26000 (ohne Anmeldung, nur LAN).
#
# DHCP macht weiter der Router. Einmalig in iVentoy: DHCP Server Mode = "External",
# Server-IP 10.0.0.5, dann Start. Im Router (DHCP, Netzwerk-Boot): Next-Server 10.0.0.5,
# Bootdateien siehe Weboberflaeche (iventoy_loader_16000_...).
# UDP 67 bleibt absichtlich zu: Selbst im falschen Modus kann iVentoy so keine Adressen
# im LAN verteilen.
let
  cfg = config.nas;
  isoDir = "${cfg.mediaDir}/ISOs";
  stateDir = "/var/lib/iventoy";

  iventoy = pkgs.stdenv.mkDerivation rec {
    pname = "iventoy";
    version = "1.0.47";
    src = pkgs.fetchurl {
      url = "https://github.com/ventoy/PXE/releases/download/v${version}/iventoy-${version}-linux-x86_64-free.tar.gz";
      sha256 = "d6c12abc37558e9bb791089bdac6e1cc7ffe402b2b0f4bef6fdc5c3aa51c6a4b";
    };
    nativeBuildInputs = [ pkgs.patchelf ];
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true; # mitgelieferte Bibliotheken nicht strippen/umschreiben
    # Vorgebautes Programm: Lader und Bibliothekspfad auf den Nix-Store zeigen lassen
    installPhase = ''
      mkdir -p $out/share/iventoy
      cp -r . $out/share/iventoy/
      lib=$out/share/iventoy/lib
      rpath=$lib/lin64:${pkgs.glibc}/lib
      patchelf --set-interpreter ${pkgs.stdenv.cc.bintools.dynamicLinker} --set-rpath $rpath $lib/iventoy
      for so in $lib/lin64/*.so*; do patchelf --set-rpath $rpath $so; done
    '';
  };
in
{
  # iVentoy erwartet seine Dateien im Arbeitsverzeichnis und schreibt dort Konfiguration
  # (data/config.dat) und Logs. Programmdateien kommen bei jedem Start frisch aus dem Paket,
  # die Konfiguration bleibt erhalten.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root -" # Logs lesbar (keine Geheimnisse)
    "d ${stateDir}/iso 0755 root root -"
  ];

  systemd.services.iventoy = {
    description = "iVentoy PXE-Server (Boot von ISO-Dateien uebers Netz)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ isoDir ];
    environment = {
      IVENTOY_API_ALL = "1"; # Weboberflaeche aus dem LAN, nicht nur localhost
      IVENTOY_AUTO_RUN = "1"; # PXE-Dienst nach Neustart automatisch starten (sobald konfiguriert)
    };
    preStart = ''
      cd ${stateDir}
      for d in data doc driver repo user; do
        cp -rT --no-preserve=mode,ownership ${iventoy}/share/iventoy/$d $d
      done
      mkdir -p log/client log/history
      # Programm als echte Datei hierher kopieren: iVentoy leitet sein Arbeitsverzeichnis vom
      # Ort der Programmdatei ab (ein Verweis in den Nix-Store endete mit Exit 255)
      rm -rf lib
      cp -rT --no-preserve=mode,ownership ${iventoy}/share/iventoy/lib lib
      chmod 755 lib/iventoy
      cp -f ${iventoy}/share/iventoy/version.txt version.txt
    '';
    serviceConfig = {
      Type = "forking"; # das Programm geht selbst in den Hintergrund
      PIDFile = "/run/iventoy.pid";
      WorkingDirectory = stateDir;
      ExecStart = "${stateDir}/lib/iventoy";
      BindPaths = [ "${isoDir}:${stateDir}/iso" ];
      Restart = "on-failure";
      TimeoutStartSec = 60;
    };
  };

  # 26000 Weboberflaeche, 16000 HTTP fuer Boot-Dateien, 10809 NBD (ISO-Inhalt), 69 TFTP
  networking.firewall.interfaces.${cfg.lanInterface} = {
    allowedTCPPorts = [ 26000 16000 10809 ];
    allowedUDPPorts = [ 69 ];
  };
}
