{ config, lib, pkgs, ... }:

# Mylar3: Comic-Verwaltung wie Kapowarr, sucht aber zusaetzlich ueber Torznab/Newznab-Indexer
# (Prowlarr) und Usenet (SABnzbd), nicht nur GetComics. Laeuft zum Vergleich neben Kapowarr,
# mit eigener Bibliothek (${libraryDir}), damit sich beide nicht in die Quere kommen.
# Nicht in nixpkgs, deshalb hier gepackt; laeuft nativ, kein Container. http://10.0.0.5:8092
#
# Einrichtung (Settings in der Oberflaeche, Zugangsdaten nicht im Repo):
#   Web Interface: ComicVine-API-Key, Comic Location /mnt/tank/media/Comics-Mylar
#   Download Settings: SABnzbd http://192.168.15.1:8085 (Kategorie comics), qBittorrent
#   http://192.168.15.1:8080 (Ordner + Folder Monitor /mnt/fast/incomplete/mylar-torrents), DDL .../mylar-ddl
#   Indexer kommen per Prowlarr (Settings -> Apps -> Mylar, URL http://10.0.0.5:8092)
let
  cfg = config.nas;
  port = 8092;
  dataDir = "${cfg.servicesDir}/mylar3";
  libraryDir = "${cfg.mediaDir}/Comics-Mylar";
  # Torrent- und DDL-Zwischenablage auf der NVMe (Dataset ohne Snapshots, wie qBittorrent),
  # damit Downloads und der Ordner-Monitor die HDDs nicht wecken.
  incompleteDir = "/mnt/${cfg.fastPool}/incomplete";
  torrentDir = "${incompleteDir}/mylar-torrents";
  ddlDir = "${incompleteDir}/mylar-ddl";

  mylar3 = pkgs.stdenv.mkDerivation rec {
    pname = "mylar3";
    version = "0.8.3";
    src = pkgs.fetchFromGitHub {
      owner = "mylar3";
      repo = "mylar3";
      rev = "v${version}";
      hash = "sha256-TyawpjRbF5ux7hmccB7/hqADIEPNGv4OLOW0/amVXbQ=";
    };
    dontBuild = true;
    # pystun wird nur fuer SAB auf fremdem Rechner gebraucht (HTTP_HOST ist hier lokal),
    # user_agent2 importiert der Code nirgends; die Startpruefung wuerde sonst abbrechen.
    # weekly_info: ausserhalb von 2025 liefert strftime einen String -> TypeError im Pull-List-Job.
    postPatch = ''
      sed -i '/^pystun/d;/^user_agent2/d' requirements.txt
      substituteInPlace mylar/helpers.py --replace-fail \
        'current_weeknumber = todaydate.strftime("%U")' \
        'current_weeknumber = int(todaydate.strftime("%U"))'
    '';
    installPhase = ''
      mkdir -p $out/share/mylar3
      cp -r . $out/share/mylar3/
    '';
  };

  # imghdr fehlt ab Python 3.13, daher 3.12. cfscrape (Cloudflare-Umgehung fuer alte
  # Torrent-Seiten) will urllib3 < 2; DEFAULT_CIPHERS gibt es dort nicht mehr.
  pythonBase = pkgs.python312.override {
    self = pythonBase;
    packageOverrides = self: super: {
      cfscrape = super.cfscrape.overridePythonAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace cfscrape/__init__.py --replace-fail \
            "from urllib3.util.ssl_ import create_urllib3_context, DEFAULT_CIPHERS" \
            "from urllib3.util.ssl_ import create_urllib3_context
          DEFAULT_CIPHERS = 'DEFAULT'"
        '';
      });
    };
  };
  python = pythonBase.withPackages (ps: with ps; [
    apscheduler beautifulsoup4 cfscrape cheroot cherrypy feedparser mako natsort packaging
    pillow portend pycryptodome pytz rarfile requests pysocks simplejson six tenacity
    tzlocal urllib3 setuptools
  ]);
in
{
  users.users.mylar = {
    isSystemUser = true;
    group = "media";
    home = dataDir;
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 mylar media -"
    "d ${libraryDir} 2775 mylar media -"
    "d ${torrentDir} 2775 mylar media -"
    "d ${ddlDir} 2775 mylar media -"
  ];

  systemd.services.mylar3 = {
    description = "Mylar3 (Comics)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir incompleteDir ];
    # bsdtar fuer CBR (rarfile), ohne unfreies unrar
    path = [ pkgs.libarchive ];
    serviceConfig = {
      User = "mylar";
      Group = "media";
      UMask = "0002";
      ExecStart = "${python}/bin/python3 ${mylar3}/share/mylar3/Mylar.py --nolaunch --quiet --datadir ${dataDir} --port ${toString port}";
      Restart = "on-failure";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ dataDir cfg.mediaDir incompleteDir ];
    };
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
