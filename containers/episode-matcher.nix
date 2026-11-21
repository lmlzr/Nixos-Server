{ config, lib, pkgs, ... }:

# MKV Episode Matcher: erkennt bei DVD-/Blu-ray-Rips (title_t00.mkv ...), welche Folge das ist,
# und benennt sie um in "Serie - S01E02 - Titel.mkv". Dazu wandelt es ein paar Minuten Ton
# per Whisper in Text um und vergleicht ihn mit den Untertiteln der Staffel (OpenSubtitles,
# Episodenliste von TMDb). Weboberflaeche: http://10.0.0.5:8001
#
# Einrichten (einmalig, in der Oberflaeche unter Settings): TMDb "API Key" (v3, 32 Zeichen,
# nicht das Lese-Token) und OpenSubtitles.com-Zugang (API-Key aus dem Konto, Benutzer, Passwort).
# Gespeichert in ${dataDir}/.mkv-episode-matcher/config.json.
#
# Ordner muss "Serie/Season N/" heissen, z. B. Transcode/ARM/completed/tv/Doctor Who (2005)/Season 1/
# (Serie und Staffel liest das Programm aus den Ordnernamen). Benannt wird an Ort und Stelle,
# danach mit Sonarr (Manueller Import) in die Bibliothek uebernehmen.
# Kommandozeile: docker exec -it episode-matcher mkv-match match "<ordner>" --dry-run [--tmdb-id 57243]
# Schon benannte Staffel pruefen (findet falsch nummerierte Folgen, aendert nichts):
#   docker exec episode-matcher episode-verify "/mnt/tank/media/TV/<Serie>/Season 03" [--tmdb-id N]
#
# Es gibt kein fertiges Image: python:3.12-slim (das Programm braucht Python < 3.13), das Paket
# wird beim ersten Start in ${dataDir}/venv installiert (~1,1 GB, ~2 min). Whisper laeuft auf der
# CPU (int8, Modell "small"); die Quadro P400 kann kein schnelles float16 und gehoert Jellyfin.
let
  cfg = config.nas;
  version = "1.3.6";
  # faster-whisper 1.2.1 ruft av.open(..., metadata_errors=) auf, das gibt es ab PyAV 18 nicht mehr
  # (jede Spracherkennung schlug mit TypeError fehl). 17.1 hat fertige Wheels und geht.
  pipPins = ''"av<18"'';
  stamp = "${version}+av17";
  port = 8001;
  dataDir = "${cfg.servicesDir}/episode-matcher";
  transcode = "${cfg.mediaDir}/Transcode";
  # ffmpeg nimmt ohne -map die "beste" Tonspur (meist die mit den meisten Kanaelen, bei den
  # Rips oft Deutsch 5.1). Die Vergleichs-Untertitel sind Englisch, deshalb fuer den Ton-
  # Ausschnitt die englische Spur waehlen, wenn es eine gibt. Alle anderen Aufrufe unveraendert.
  ffmpegEng = pkgs.writeShellScriptBin "ffmpeg" ''
    real=${pkgs.ffmpeg-headless}/bin/ffmpeg
    in= prev= vn=
    for a in "$@"; do
      [ "$prev" = "-i" ] && in=$a
      [ "$a" = "-vn" ] && vn=1
      prev=$a
    done
    if [ -n "$vn" ] && [ -n "$in" ]; then
      idx=$(${pkgs.ffmpeg-headless}/bin/ffprobe -v error -select_streams a \
        -show_entries stream=index:stream_tags=language -of csv=p=0 "$in" \
        | ${pkgs.gawk}/bin/awk -F, '$2=="eng"{print $1; exit}')
      if [ -n "$idx" ]; then
        out=''${@: -1}
        set -- "''${@:1:$#-1}" -map "0:$idx" "$out"
      fi
    fi
    exec "$real" "$@"
  '';
  # Prueft schon benannte Staffeln (aendert nichts), siehe episode-verify.py
  verify = pkgs.writeShellScriptBin "episode-verify" ''
    exec python ${./episode-verify.py} "$@"
  '';
  start = pkgs.writeShellScript "episode-matcher-start" ''
    set -e
    if [ "$(cat /data/venv/.version 2>/dev/null)" != "${stamp}" ]; then
      rm -rf /data/venv
      python -m venv /data/venv
      /data/venv/bin/pip install --no-cache-dir --only-binary=av "mkv-episode-matcher==${version}" ${pipPins}
      echo "${stamp}" > /data/venv/.version
    fi
    # PAL-DVDs laufen 4 % schneller als die Untertitel, siehe episode-matcher-pal.py
    python ${./episode-matcher-pal.py} /data/venv/lib/python3.12/site-packages
    # Untertitelsuche: alle Ergebnisseiten, fehlende Folgen nachladen, siehe episode-matcher-subs.py
    python ${./episode-matcher-subs.py} /data/venv/lib/python3.12/site-packages
    # Specials: Season 0 und Ordner "Specials", siehe episode-matcher-specials.py
    python ${./episode-matcher-specials.py} /data/venv/lib/python3.12/site-packages
    exec mkv-match serve --host 0.0.0.0 --port ${toString port} --no-browser
  '';
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers.episode-matcher = {
      image = "python:3.12-slim-bookworm";
      ports = [ "${toString port}:${toString port}" ];
      user = "${toString config.users.users.lmlzr.uid}:989"; # Gruppe media, wie ARM/MakeMKV
      volumes = [
        "${dataDir}:/data"
        # gleicher Pfad wie auf dem Host, damit Pfade aus der Oberflaeche ueberall stimmen
        "${transcode}:${transcode}"
        # Serien und Filme schreibbar: direkt in der Bibliothek umbenennen (danach in Sonarr/
        # Radarr "Rescan"). Bis 2026-11-05 nur lesend, da scheiterte jedes Umbenennen dort.
        "${cfg.mediaDir}/TV:${cfg.mediaDir}/TV"
        "${cfg.mediaDir}/Movies:${cfg.mediaDir}/Movies"
        # ffmpeg/ffprobe und die Start-Skripte kommen aus dem Nix-Store
        "/nix/store:/nix/store:ro"
      ];
      environment = {
        HOME = "/data";
        HF_HOME = "/data/huggingface"; # Whisper-Modelle
        PATH = "/data/venv/bin:${verify}/bin:${ffmpegEng}/bin:${pkgs.ffmpeg-headless}/bin:/usr/local/bin:/usr/bin:/bin";
        CUDA_VISIBLE_DEVICES = ""; # Whisper auf der CPU
        PIP_DISABLE_PIP_VERSION_CHECK = "1";
        TZ = config.time.timeZone;
      };
      entrypoint = "${start}";
      # Untertitel laedt das Programm erst ins aktuelle Verzeichnis (sonst "/", nicht beschreibbar)
      workdir = "/data";
      autoStart = true;
    };
  };

  systemd.services.docker-episode-matcher = {
    unitConfig.RequiresMountsFor = [ cfg.servicesDir cfg.mediaDir ];
    preStart = ''
      install -d -m 0750 -o ${toString config.users.users.lmlzr.uid} -g 989 ${dataDir}
    '';
  };

  # Sicherheitsnetz: taeglich 05:00 neu starten (frische OpenSubtitles-Anmeldung, haengende
  # Zustaende weg), aber nur, wenn gerade nichts zugeordnet wird: kein mkv-match/episode-verify
  # per docker exec und der Server selbst unter 5 % CPU (ein Scan aus der Oberflaeche rechnet).
  systemd.services.episode-matcher-restart = {
    description = "Episode Matcher neu starten, wenn untaetig";
    path = [ pkgs.docker pkgs.gawk pkgs.coreutils pkgs.systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      systemctl -q is-active docker-episode-matcher.service || exit 0
      if docker top episode-matcher -eo pid,args | grep -q -E "mkv-match match|episode-verify"; then
        echo "Zuordnung laeuft (docker exec), kein Neustart"; exit 0
      fi
      cpu=$(docker stats --no-stream --format '{{.CPUPerc}}' episode-matcher | tr -d '%')
      if awk -v c="$cpu" 'BEGIN{exit !(c >= 5)}'; then
        echo "Server rechnet gerade (CPU $cpu %), kein Neustart"; exit 0
      fi
      echo "Untaetig (CPU $cpu %), starte neu"
      systemctl restart docker-episode-matcher.service
    '';
  };
  systemd.timers.episode-matcher-restart = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*-*-* 05:00:00";
  };

  networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ port ];
}
