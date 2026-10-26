{ config, lib, pkgs, ... }:

let
  cfg = config.services.pterodactyl;
  panelCfg = cfg.panel;
  wingsCfg = cfg.wings;

  panel = pkgs.callPackage ./panel-package.nix { inherit (panelCfg) dataDir; };
  wings = pkgs.callPackage ./wings-package.nix { };
  php = panel.phpPackage;

  user = "pterodactyl";
  redisSocket = config.services.redis.servers.pterodactyl.unixSocket;

  # Nicht geheime Einstellungen; APP_KEY und HASHIDS_SALT erzeugt das Setup selbst
  env = {
    APP_ENV = "production";
    APP_DEBUG = "false";
    APP_THEME = "pterodactyl";
    APP_TIMEZONE = panelCfg.timezone;
    APP_URL = panelCfg.appUrl;
    APP_LOCALE = "de";
    APP_ENVIRONMENT_ONLY = "true";
    TRUSTED_PROXIES = lib.concatStringsSep "," panelCfg.trustedProxies;

    DB_CONNECTION = "mysql";
    DB_HOST = "localhost";
    DB_SOCKET = "/run/mysqld/mysqld.sock"; # Anmeldung per unix_socket, kein Passwort
    DB_DATABASE = "panel";
    DB_USERNAME = user;
    DB_PASSWORD = "";

    REDIS_SCHEME = "unix";
    REDIS_PATH = redisSocket;
    CACHE_DRIVER = "redis";
    SESSION_DRIVER = "redis";
    QUEUE_CONNECTION = "redis";

    HASHIDS_LENGTH = "8";

    # Ohne SMTP landen Mails (z. B. Passwort-Reset) nur im Log
    MAIL_MAILER = "log";
    MAIL_FROM_ADDRESS = "no-reply@neotokyo";
    MAIL_FROM_NAME = "Pterodactyl Panel";
  } // panelCfg.settings;

  artisan = "${php}/bin/php ${panel}/artisan";

  setupScript = pkgs.writeShellScript "pterodactyl-panel-setup" ''
    set -eu
    cd ${panelCfg.dataDir}

    mkdir -p cache secrets \
      storage/app/public storage/app/private storage/clockwork \
      storage/framework/cache/data storage/framework/sessions storage/framework/views \
      storage/logs

    # Schluessel einmalig erzeugen. APP_KEY sichern! Ohne ihn sind API-Keys,
    # Node-Tokens und 2FA-Daten nicht mehr lesbar.
    umask 077
    [ -s secrets/app-key ] || printf 'base64:%s' "$(head -c 32 /dev/urandom | base64)" > secrets/app-key
    [ -s secrets/hashids-salt ] || head -c 48 /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9' | cut -c1-20 > secrets/hashids-salt

    {
      ${lib.concatStringsSep "\n      " (lib.mapAttrsToList (n: v: "echo ${lib.escapeShellArg "${n}=\"${v}\""}") env)}
      echo "APP_KEY=\"$(cat secrets/app-key)\""
      echo "HASHIDS_SALT=\"$(cat secrets/hashids-salt)\""
      ${lib.optionalString (panelCfg.mailPassword.file != null) ''
        echo "MAIL_PASSWORD=\"$(${pkgs.gnused}/bin/sed -n 's/^${panelCfg.mailPassword.key}=//p' "$CREDENTIALS_DIRECTORY/smtp")\""
      ''}
    } > .env.tmp
    mv .env.tmp .env

    ${artisan} optimize:clear
    ${artisan} migrate --seed --force
  '';

  # Aufruf: sudo pterodactyl-artisan p:user:make
  artisanWrapper = pkgs.writeShellScriptBin "pterodactyl-artisan" ''
    cd ${panel}
    exec ${config.security.wrapperDir}/sudo -u ${user} ${artisan} "$@"
  '';

  commonServiceConfig = {
    User = user;
    Group = user;
    WorkingDirectory = panel;
    ReadWritePaths = [ panelCfg.dataDir ];
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    NoNewPrivileges = true;
  };
in
{
  options.services.pterodactyl = {
    panel = {
      enable = lib.mkEnableOption "Pterodactyl Panel";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8090;
        description = "Port des nginx-vHosts fuer das Panel.";
      };

      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://10.0.0.5:${toString panelCfg.port}";
        description = "Adresse, unter der das Panel im Browser aufgerufen wird.";
      };

      timezone = lib.mkOption {
        type = lib.types.str;
        default = if config.time.timeZone != null then config.time.timeZone else "UTC";
        defaultText = lib.literalExpression "config.time.timeZone";
      };

      trustedProxies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "10.100.0.1" ];
        description = "Reverse-Proxys (z. B. der VPS), deren X-Forwarded-Header vertraut wird.";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/pterodactyl-panel";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = { MAIL_MAILER = "smtp"; MAIL_HOST = "smtp.example.com"; };
        description = "Zusaetzliche/ueberschriebene .env-Werte (keine Geheimnisse, landen im Nix-Store).";
      };

      mailPassword = {
        file = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/home/lmlzr/smtp-keys.env";
          description = "Datei mit dem SMTP-Passwort als KEY=Wert-Zeile; wird per LoadCredential gelesen, nicht im Nix-Store.";
        };
        key = lib.mkOption {
          type = lib.types.str;
          default = "TOKEN_PTERODACTYL";
          description = "Name der Zeile in mailPassword.file.";
        };
      };
    };

    wings = {
      enable = lib.mkEnableOption "Pterodactyl Wings (startet die Gameserver in Docker)";

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      apiPort = lib.mkOption {
        type = lib.types.port;
        default = 8443; # 8080 ist von qBittorrent belegt
        description = "Muss mit dem 'Daemon Port' der Node im Panel uebereinstimmen.";
      };

      sftpPort = lib.mkOption {
        type = lib.types.port;
        default = 2022;
      };

      gamePorts = lib.mkOption {
        type = lib.types.submodule {
          options = {
            from = lib.mkOption { type = lib.types.port; };
            to = lib.mkOption { type = lib.types.port; };
          };
        };
        default = { from = 25565; to = 25600; };
        description = "Portbereich fuer die Gameserver (TCP und UDP), im Panel als Allocations anlegen.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf panelCfg.enable {
      users.users.${user} = {
        isSystemUser = true;
        group = user;
        extraGroups = [ config.services.redis.servers.pterodactyl.group ];
      };
      users.groups.${user} = { };

      services.mysql = {
        enable = true;
        package = lib.mkDefault pkgs.mariadb;
        ensureDatabases = [ "panel" ];
        ensureUsers = [
          {
            name = user;
            ensurePermissions."panel.*" = "ALL PRIVILEGES";
          }
        ];
      };

      services.redis.servers.pterodactyl = {
        enable = true;
        port = 0; # nur Unix-Socket
      };

      systemd.services.pterodactyl-panel-setup = {
        description = "Pterodactyl Panel: Konfiguration und Datenbank-Migration";
        after = [ "mysql.service" "redis-pterodactyl.service" ];
        requires = [ "mysql.service" "redis-pterodactyl.service" ];
        before = [ "phpfpm-pterodactyl.service" ];
        requiredBy = [ "phpfpm-pterodactyl.service" ];
        restartTriggers = [ panel ];
        # Laravel spielt das Datenbankschema beim ersten Start per mysql-Client ein
        path = [ config.services.mysql.package ];
        serviceConfig = commonServiceConfig // {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "pterodactyl-panel";
          StateDirectoryMode = "0750";
          LoadCredential = lib.optional (panelCfg.mailPassword.file != null) "smtp:${panelCfg.mailPassword.file}";
          ExecStart = setupScript;
        };
      };

      services.phpfpm.pools.pterodactyl = {
        inherit user;
        group = user;
        phpPackage = php;
        settings = {
          "listen.owner" = config.services.nginx.user;
          "listen.group" = config.services.nginx.group;
          "listen.mode" = "0660";
          "pm" = "dynamic";
          "pm.max_children" = 16;
          "pm.start_servers" = 2;
          "pm.min_spare_servers" = 2;
          "pm.max_spare_servers" = 4;
          "pm.max_requests" = 500;
        };
      };

      services.nginx = {
        enable = true;
        virtualHosts.pterodactyl = {
          listen = [ { addr = "0.0.0.0"; port = panelCfg.port; } ];
          root = "${panel}/public";
          extraConfig = ''
            index index.php;
            client_max_body_size 100m;
            client_body_timeout 120s;
            sendfile off;
          '';
          locations."/".tryFiles = "$uri $uri/ /index.php?$query_string";
          locations."~ \\.php$".extraConfig = ''
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:${config.services.phpfpm.pools.pterodactyl.socket};
            include ${config.services.nginx.package}/conf/fastcgi.conf;
            fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
            fastcgi_param HTTP_PROXY "";
            fastcgi_intercept_errors off;
            fastcgi_buffer_size 16k;
            fastcgi_buffers 4 16k;
            fastcgi_connect_timeout 300;
            fastcgi_send_timeout 300;
            fastcgi_read_timeout 300;
          '';
          locations."~ /\\.ht".extraConfig = "deny all;";
        };
      };

      # Warteschlange (pteroq)
      systemd.services.pterodactyl-queue = {
        description = "Pterodactyl Queue Worker";
        after = [ "pterodactyl-panel-setup.service" ];
        requires = [ "pterodactyl-panel-setup.service" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ panel ];
        serviceConfig = commonServiceConfig // {
          ExecStart = "${artisan} queue:work --queue=high,standard,low --sleep=3 --tries=3";
          Restart = "always";
          RestartSec = "5s";
        };
      };

      # Ersatz fuer den Cronjob "* * * * * php artisan schedule:run"
      systemd.services.pterodactyl-schedule = {
        description = "Pterodactyl Scheduler";
        after = [ "pterodactyl-panel-setup.service" ];
        requires = [ "pterodactyl-panel-setup.service" ];
        serviceConfig = commonServiceConfig // {
          Type = "oneshot";
          ExecStart = "${artisan} schedule:run";
        };
      };
      systemd.timers.pterodactyl-schedule = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "minutely";
          AccuracySec = "1s";
        };
      };

      environment.systemPackages = [ artisanWrapper ];

      networking.firewall.allowedTCPPorts = [ panelCfg.port ];
    })

    (lib.mkIf wingsCfg.enable {
      virtualisation.docker.enable = true;

      # config.yml kommt aus dem Panel (Admin -> Nodes -> Configuration)
      systemd.tmpfiles.rules = [ "d /etc/pterodactyl 0700 root root -" ];

      systemd.services.wings = {
        description = "Pterodactyl Wings";
        after = [ "docker.service" "network-online.target" ];
        requires = [ "docker.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        # Startet erst, wenn die Config aus dem Panel hinterlegt ist
        unitConfig.ConditionPathExists = "/etc/pterodactyl/config.yml";
        serviceConfig = {
          ExecStart = "${wings}/bin/wings --config /etc/pterodactyl/config.yml";
          Restart = "on-failure";
          RestartSec = "5s";
          LimitNOFILE = 4096;
        };
      };

      environment.systemPackages = [ wings ];

      networking.firewall = lib.mkIf wingsCfg.openFirewall {
        allowedTCPPorts = [ wingsCfg.apiPort wingsCfg.sftpPort ];
        allowedTCPPortRanges = [ wingsCfg.gamePorts ];
        allowedUDPPortRanges = [ wingsCfg.gamePorts ];
      };
    })
  ];
}
