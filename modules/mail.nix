{ config, lib, pkgs, ... }:

# Mailversand ueber Proton Mail (SMTP-Token, eigene Domain). Stellt sendmail bereit
# (msmtp) fuer smartd, ZED und die OnFailure-Benachrichtigung notify-mail@.
# Der Token steht nicht im Repo, sondern in envFile (Zeile TOKEN_NEOTOKYO=...).
let
  cfg = config.nas.mail;
in
{
  options.nas.mail = {
    from = lib.mkOption {
      type = lib.types.str;
      default = "service@lmlzr.com";
      description = "Absender; die Adresse, fuer die der SMTP-Token erstellt wurde.";
    };

    alertTo = lib.mkOption {
      type = lib.types.str;
      default = "service@lmlzr.com";
      description = "Empfaenger fuer Warnungen (root, smartd, ZED, fehlgeschlagene Dienste).";
    };

    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/home/lmlzr/smtp-keys.env";
      description = "Datei mit TOKEN_NEOTOKYO=<SMTP-Token>; nur fuer root/lmlzr lesbar.";
    };
  };

  config = {
    programs.msmtp = {
      enable = true;
      setSendmail = true;
      defaults = {
        aliases = "/etc/aliases";
        port = 587;
        tls = true;
        tls_starttls = true;
        auth = true;
      };
      accounts.default = {
        host = "smtp.protonmail.ch";
        from = cfg.from;
        user = cfg.from;
        passwordeval = "${pkgs.gnused}/bin/sed -n 's/^TOKEN_NEOTOKYO=//p' ${cfg.envFile}";
      };
    };

    # Mails an lokale Benutzer (root, cron, ...) gehen an alertTo
    environment.etc.aliases.text = ''
      root: ${cfg.alertTo}
      default: ${cfg.alertTo}
    '';

    # Benachrichtigung bei fehlgeschlagenen Diensten:
    #   systemd.services.<name>.onFailure = [ "notify-mail@%n.service" ];
    systemd.services."notify-mail@" = {
      description = "Mail: %i ist fehlgeschlagen";
      serviceConfig.Type = "oneshot";
      path = [ pkgs.msmtp pkgs.systemd ];
      scriptArgs = "%i";
      script = ''
        unit="$1"
        {
          echo "To: ${cfg.alertTo}"
          echo "From: neotokyo <${cfg.from}>"
          echo "Subject: [neotokyo] $unit fehlgeschlagen"
          echo "Content-Type: text/plain; charset=UTF-8"
          echo
          systemctl status --no-pager --lines=40 "$unit" || true
        } | msmtp ${cfg.alertTo}
      '';
    };
  };
}
