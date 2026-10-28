{ config, lib, pkgs, ... }:

# LiteLLM: ein Endpunkt (OpenAI-kompatibel) fuer viele KI-Anbieter, mit Weboberflaeche fuer
# Modelle, eigene API-Keys pro Anwendung und Kostenuebersicht. http://10.0.0.5:4000 (UI: /ui)
#
# Anwendungen sprechen LiteLLM wie die OpenAI-API an:
#   Base-URL  http://10.0.0.5:4000/v1    API-Key  ein in der UI erzeugter "Virtual Key"
#
# Anbieter-Keys, zwei Wege (beide gehen gleichzeitig):
#   1. In der UI unter "Models" -> "Add Model" (Key wird verschluesselt in der Datenbank gespeichert)
#   2. In /etc/secrets/litellm.env die passende Zeile einkommentieren, dann
#      sudo systemctl restart docker-litellm. Danach sind alle Modelle dieses Anbieters ueber
#      "<anbieter>/<modell>" nutzbar, z. B. "openai/gpt-4o-mini", "anthropic/claude-sonnet-4-5",
#      "gemini/gemini-2.5-flash", "openrouter/<modell>" (siehe providers unten).
#
# /etc/secrets/litellm.env wird beim ersten Start erzeugt (Master-Key, UI-Login, DB-Passwort):
#   sudo cat /etc/secrets/litellm.env
# LITELLM_SALT_KEY darin nie aendern: damit sind die in der Datenbank gespeicherten Keys verschluesselt.
#
# Daten: /mnt/fast/services/litellm/db (PostgreSQL fuer Keys, Modelle, Nutzungsstatistik)
let
  cfg = config.nas;
  port = 4000;
  dbPort = 5433; # 5432 belegt die Immich-Datenbank
  dataDir = "${cfg.servicesDir}/litellm";
  secrets = "/etc/secrets/litellm.env";
  dbSecrets = "/etc/secrets/litellm-db.env";

  # Anbieter -> Umgebungsvariable mit dem API-Key. Fuer jeden gibt es eine Wildcard-Route
  # "<anbieter>/*"; sie funktioniert, sobald der Key in litellm.env gesetzt ist.
  providers = {
    openai = "OPENAI_API_KEY";
    anthropic = "ANTHROPIC_API_KEY";
    gemini = "GEMINI_API_KEY";
    mistral = "MISTRAL_API_KEY";
    groq = "GROQ_API_KEY";
    deepseek = "DEEPSEEK_API_KEY";
    xai = "XAI_API_KEY";
    openrouter = "OPENROUTER_API_KEY";
    together_ai = "TOGETHERAI_API_KEY";
    perplexity = "PERPLEXITYAI_API_KEY";
    cohere = "COHERE_API_KEY";
  };

  litellmConfig = (pkgs.formats.yaml { }).generate "litellm-config.yaml" {
    model_list = lib.mapAttrsToList (p: env: {
      model_name = "${p}/*";
      litellm_params = {
        model = "${p}/*";
        api_key = "os.environ/${env}";
      };
    }) providers;
    litellm_settings = {
      drop_params = true; # Parameter, die ein Anbieter nicht kennt, weglassen statt Fehler
    };
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
      database_url = "os.environ/DATABASE_URL";
      store_model_in_db = true; # Modelle aus der UI bleiben gespeichert
    };
  };

  genSecrets = pkgs.writeShellScript "litellm-secrets" ''
    set -eu
    umask 077
    rand() { ${pkgs.openssl}/bin/openssl rand -hex 24; }
    if [ ! -e ${dbSecrets} ]; then
      echo "POSTGRES_PASSWORD=$(rand)" > ${dbSecrets}
    fi
    if [ ! -e ${secrets} ]; then
      pw=$(${pkgs.gnused}/bin/sed -n 's/^POSTGRES_PASSWORD=//p' ${dbSecrets})
      {
        echo "# LiteLLM, siehe containers/litellm.nix. Nach Aenderungen: sudo systemctl restart docker-litellm"
        echo "LITELLM_MASTER_KEY=sk-$(rand)"
        echo "LITELLM_SALT_KEY=sk-$(rand)"
        echo "UI_USERNAME=admin"
        echo "UI_PASSWORD=$(rand)"
        echo "DATABASE_URL=postgresql://litellm:$pw@127.0.0.1:${toString dbPort}/litellm"
        echo
        echo "# Anbieter-Keys: Zeile einkommentieren und Key eintragen"
        ${lib.concatMapStrings (env: ''
          echo "#${env}="
        '') (lib.attrValues providers)}
      } > ${secrets}
    fi
  '';
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers.litellm-db = {
      image = "postgres:17.10-alpine";
      ports = [ "127.0.0.1:${toString dbPort}:5432" ];
      volumes = [ "${dataDir}/db:/var/lib/postgresql/data" ];
      environment = {
        POSTGRES_USER = "litellm";
        POSTGRES_DB = "litellm";
      };
      environmentFiles = [ dbSecrets ];
      autoStart = true;
    };
    containers.litellm = {
      image = "ghcr.io/berriai/litellm-database:v1.99.4";
      volumes = [ "${litellmConfig}:/app/config.yaml:ro" ];
      cmd = [ "--config" "/app/config.yaml" "--port" (toString port) ];
      environmentFiles = [ secrets ];
      environment = {
        STORE_MODEL_IN_DB = "True";
        TZ = config.time.timeZone;
      };
      # Host-Netz: erreicht die Datenbank auf 127.0.0.1 und lokale Dienste (z. B. spaeter Ollama)
      extraOptions = [ "--network=host" ];
      dependsOn = [ "litellm-db" ];
      autoStart = true;
    };
  };

  systemd.services.litellm-secrets = {
    description = "LiteLLM: Secrets beim ersten Start erzeugen";
    wantedBy = [ "multi-user.target" ];
    before = [ "docker-litellm-db.service" "docker-litellm.service" ];
    unitConfig.RequiresMountsFor = [ "/etc/secrets" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = genSecrets;
    };
  };

  systemd.services.docker-litellm-db = {
    requires = [ "litellm-secrets.service" ];
    after = [ "litellm-secrets.service" ];
    unitConfig.RequiresMountsFor = [ cfg.servicesDir ];
    preStart = ''
      install -d -m 0750 ${dataDir}
      install -d -m 0700 ${dataDir}/db
    '';
  };
  systemd.services.docker-litellm = {
    requires = [ "litellm-secrets.service" ];
    after = [ "litellm-secrets.service" ];
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
