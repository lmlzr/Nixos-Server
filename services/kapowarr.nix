{ config, lib, pkgs, ... }:

# Kapowarr: Comic-Bibliothek im Stil von Sonarr. Serien (Volumes) aus ComicVine hinzufuegen,
# fehlende und neue Hefte kommen per Direkt-Download von GetComics (kein Torrent/Usenet).
# Nicht in nixpkgs, deshalb hier gepackt; laeuft nativ, kein Container. http://10.0.0.5:5656
#
# Einrichtung in der Oberflaeche:
#   Settings -> General: ComicVine-API-Key (kostenlos, comicvine.gamespot.com/api)
#   Settings -> Media Management: Root Folder /mnt/tank/media/Comics
# Komga findet neue Hefte in der Bibliothek "Comics" beim naechsten Scan.
let
  cfg = config.nas;
  port = 5656;
  dataDir = "${cfg.servicesDir}/kapowarr";
  tempDir = "${cfg.mediaDir}/Comics-Downloads";

  kapowarr = pkgs.stdenv.mkDerivation rec {
    pname = "kapowarr";
    version = "1.3.2";
    src = pkgs.fetchFromGitHub {
      owner = "Casvt";
      repo = "Kapowarr";
      rev = "V${version}";
      hash = "sha256-W4HC+evNOYd8JMTr3zzraT+ZC8WXr4n/exEiOj39cRo=";
    };
    # mitgeliefertes rar (Entpacken von CBR) ist dynamisch gelinkt
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/share/kapowarr
      cp -r Kapowarr.py backend frontend pyproject.toml $out/share/kapowarr/
      rm $out/share/kapowarr/backend/lib/rar_bsd_64 $out/share/kapowarr/backend/lib/rar_windows_64.exe
    '';
  };

  python = pkgs.python3.withPackages (ps: [
    ps.typing-extensions ps.requests ps.pysocks ps.beautifulsoup4 ps.flask ps.waitress
    ps.cryptography ps.aiohttp ps.flask-socketio ps.websocket-client ps.cron-converter
    (ps.buildPythonPackage rec {
      pname = "bencoding";
      version = "0.2.6";
      pyproject = true;
      build-system = [ ps.setuptools ];
      src = ps.fetchPypi {
        inherit pname version;
        hash = "sha256-Q8zjHUhj4p1rxhFVHU6fJlK+KZXp1eFbRtg4PxgNREA=";
      };
    })
  ]);

  # Kapowarr schreibt neben seinen Code (Upload beim DB-Import, Standard-Backupordner),
  # deshalb laeuft eine Kopie im Datenordner; erneuert, wenn sich das Paket aendert.
  prepare = pkgs.writeShellScript "kapowarr-prepare" ''
    set -eu
    app=${dataDir}/app
    if [ "$(cat $app/.paket 2>/dev/null)" != "${kapowarr}" ]; then
      mkdir -p $app
      rm -rf $app/backend $app/frontend $app/Kapowarr.py $app/pyproject.toml
      cp -r --no-preserve=mode ${kapowarr}/share/kapowarr/. $app/
      chmod +x $app/backend/lib/rar_linux_64
      echo ${kapowarr} > $app/.paket
    fi
  '';
in
{
  users.users.kapowarr = {
    isSystemUser = true;
    group = "media";
    home = dataDir;
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 kapowarr media -"
    "d ${tempDir} 2775 kapowarr media -"
  ];

  systemd.services.kapowarr = {
    description = "Kapowarr (Comics)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir ];
    serviceConfig = {
      User = "kapowarr";
      Group = "media";
      UMask = "0002"; # Comics gehoeren root:media (2775/664)
      ExecStartPre = prepare;
      ExecStart = "${python}/bin/python3 ${dataDir}/app/Kapowarr.py -d ${dataDir}/db -l ${dataDir}/logs -t ${tempDir} -o 0.0.0.0 -p ${toString port}";
      Restart = "on-failure";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ dataDir cfg.mediaDir ];
    };
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
