{ config, lib, pkgs, ... }:

# Lokale KI fuer Mealie (Rezepte aus Text, Foto und Video). Standardmaessig AUS:
# einschalten mit `nas.ai.enable = true;` in configuration.nix, dann Rebuild.
#
#   Ollama    http://10.0.0.5:11434/v1   Text- und Bildmodell (OpenAI-kompatibel), CPU
#   Speaches  http://10.0.0.5:8001/v1    Spracherkennung (Whisper, OpenAI-kompatibel), CPU
#
# Beide laufen dauerhaft, belegen im Leerlauf aber kaum RAM: Modelle werden erst bei einer
# Anfrage geladen und nach 5 Minuten ohne Nutzung wieder entladen.
# Die Quadro P400 (2 GB) ist zu klein fuer diese Modelle, alles laeuft auf der CPU:
# Text ca. 1-3 min pro Rezept, Foto mehrere Minuten, Video ~Laenge des Videos + Textschritt.
# Keine Anmeldung: beide nur ueber die LAN-Schnittstelle erreichbar.
let
  cfg = config.nas.ai;
  lan = config.nas.lanInterface;
in
{
  options.nas.ai = {
    enable = lib.mkEnableOption "lokale KI (Ollama + Speaches) fuer Mealie";

    textModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen2.5:7b-instruct";
      description = "Ollama-Modell fuer Text (Rezept aus Webseite/Video-Text, Zutaten zerlegen).";
    };
    visionModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen2.5vl:7b";
      description = "Ollama-Modell, das Bilder versteht (Rezept aus Foto).";
    };
    whisperModel = lib.mkOption {
      type = lib.types.str;
      default = "Systran/faster-whisper-small";
      description = "Speaches-Modell fuer die Spracherkennung (mehrsprachig).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      host = "0.0.0.0";
      port = 11434;
      # Laedt die Modelle einmalig herunter (~10 GB, /var/lib/ollama)
      loadModels = [ cfg.textModel cfg.visionModel ];
      environmentVariables = {
        OLLAMA_KEEP_ALIVE = "5m"; # Modell nach 5 min Leerlauf aus dem RAM
        OLLAMA_MAX_LOADED_MODELS = "1"; # nie Text- und Bildmodell gleichzeitig im RAM
        OLLAMA_NUM_PARALLEL = "1";
        OLLAMA_CONTEXT_LENGTH = "16384"; # Video-Beschreibung + Transkript passen hinein
      };
    };
    # Obergrenze, damit ein Modell nie die anderen Dienste verdraengt (Modell + Kontext ~6-9 GB)
    systemd.services.ollama.serviceConfig = {
      MemoryHigh = "12G";
      MemoryMax = "14G";
      CPUWeight = 50; # bei Engpass haben Jellyfin & Co. Vorrang
    };

    virtualisation.oci-containers = {
      backend = "docker";
      containers.speaches = {
        image = "ghcr.io/speaches-ai/speaches:0.9.0-rc.3-cpu";
        ports = [ "8001:8000" ]; # 8000 belegt Portainer
        volumes = [ "${config.nas.servicesDir}/speaches:/home/ubuntu/.cache/huggingface/hub" ];
        environment = {
          STT_MODEL_TTL = "300"; # Modell nach 5 min Leerlauf entladen
          WHISPER__COMPUTE_TYPE = "int8"; # schneller auf der CPU
          WHISPER__CPU_THREADS = "6";
          ENABLE_UI = "false";
          LOG_LEVEL = "info";
        };
        autoStart = true;
      };
    };
    systemd.services.docker-speaches = {
      unitConfig.RequiresMountsFor = [ config.nas.servicesDir ];
      preStart = ''
        install -d -m 0755 -o 1000 -g 1000 ${config.nas.servicesDir}/speaches
      '';
    };

    # Speaches laedt Modelle nicht selbst nach: einmalig herunterladen (idempotent)
    systemd.services.speaches-model-download = {
      description = "Speaches: Whisper-Modell ${cfg.whisperModel} herunterladen";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker-speaches.service" ];
      requires = [ "docker-speaches.service" ];
      path = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for i in $(seq 1 60); do
          curl -sf http://127.0.0.1:8001/health >/dev/null && break
          sleep 2
        done
        curl -sf -X POST http://127.0.0.1:8001/v1/models/${cfg.whisperModel}
      '';
    };

    networking.firewall.interfaces.${lan}.allowedTCPPorts = [ 11434 8001 ];
  };
}
