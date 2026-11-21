# Patch fuer mkv-episode-matcher 1.3.6 (wird nach pip install angewendet, siehe episode-matcher.nix,
# nach episode-matcher-subs.py):
# Specials (Season 0) gingen nicht:
#  1. engine.py prueft "if not season", 0 zaehlt in Python als "keine Season": Dateien in
#     "Season 0"/"Season 00" wurden mit "Could not determine context" uebersprungen. Ein Ordner
#     "Specials" (Sonarr/Jellyfin) hatte gar keine Nummer.
#  2. subtitles.py: dasselbe bei der Season aus der API (Untertitel fielen auf den Dateinamen zurueck).
#  3. OpenSubtitles fuehrt Specials oft alle als S00E00 (Doctor Who: 89 Untertitel, alle E00), nur
#     Titel und TMDb-Folgen-ID unterscheiden sie. Die Suche pro Folge (episode_number=1..N) fand
#     daher nie etwas. Fuer Season 0 werden jetzt alle Treffer der Season geholt und ueber die
#     TMDb-Folgen-ID (sonst den Titel) der Nummer bei TMDb zugeordnet.
import sys
from pathlib import Path

base = Path(sys.argv[1]) / "mkv_episode_matcher/core"
patches = {
    base / "engine.py": [
        ("""        # Heuristic 1: Standard folder structure (Show/Season X/file.mkv)
        try:
            parent_name = video_file.parent.name
            if "season" in parent_name.lower():""",
         """        # Heuristic 1: Standard folder structure (Show/Season X/file.mkv)
        try:
            parent_name = video_file.parent.name
            if parent_name.lower() in ("specials", "special"):  # Specials-Patch
                season = 0
                show_name = video_file.parent.parent.name
            elif "season" in parent_name.lower():"""),
        ("""        # Heuristic 2: Season folder with S## pattern
        if not season:""",
         """        # Heuristic 2: Season folder with S## pattern
        if season is None:"""),
        ("""        # Heuristic 4: Extract from filename itself
        if not season:""",
         """        # Heuristic 4: Extract from filename itself
        if season is None:"""),
        ("""            if season_override:
                season = season_override

            if not show_name or not season:""",
         """            if season_override is not None:
                season = season_override

            if not show_name or season is None:"""),
    ],
    base / "providers/subtitles.py": [
        ("""                if api_season and api_episode:""",
         """                if api_season is not None and api_episode:  # Specials-Patch"""),
        # TMDb-Specials sind nicht lueckenlos nummeriert (Doctor Who: 199 Specials, Nummern bis 210)
        ("""                if expected and not 1 <= ep_num <= expected:  # Subs-Patch""",
         """                if season != 0 and expected and not 1 <= ep_num <= expected:  # Subs-Patch"""),
        ("""            def _all_pages(first):  # Subs-Patch: weitere Ergebnisseiten
                if expected and tmdb_id:""",
         """            def _specials(first):  # Specials-Patch: S00E00 per TMDb-Folgen-ID/Titel zuordnen
                import requests
                from mkv_episode_matcher.core.config_manager import get_config_manager as _gcm

                key_ = _gcm().load().tmdb_api_key
                eps = requests.get(f"https://api.themoviedb.org/3/tv/{tmdb_id}/season/0?api_key={key_}",
                                   timeout=30).json().get("episodes", [])

                import difflib

                def norm(t):  # '"Doctor Who" The End of Time: Part One' == 'The End of Time (1)'
                    t = _re.sub(r'^"[^"]*"\\s*', "", t or "").lower()
                    w = _re.sub(r"[^a-z0-9]+", " ", t).split()
                    num = {"one": "1", "two": "2", "three": "3"}
                    return " ".join(num.get(x, x) for x in w if x not in ("the", "a", "part", "prequel", "to"))

                def match(title):
                    n = norm(title)
                    if n in by_name:
                        return by_name[n]
                    # 0.9: "Evolution of the Daleks (2)" darf nicht "Revolution of the Daleks" werden
                    close = difflib.get_close_matches(n, by_name, 1, 0.9)
                    return by_name[close[0]] if close else None

                by_id = {e["id"]: e["episode_number"] for e in eps}
                by_name = {norm(e.get("name")): e["episode_number"] for e in eps if e.get("name")}
                # Season 0 bei OpenSubtitles (v. a. Minisodes, meist alle als E00)
                subs = list(first.data)
                total = getattr(first, "total_pages", 1) or 1
                for pg in range(2, min(total, 20) + 1):
                    subs += self._search_with_retry(query=None, parent_tmdb_id=tmdb_id, season_number=0,
                                                    type="episode", page=pg).data
                # Lange Specials stehen bei OpenSubtitles oft als E00 in normalen Staffeln (Doctor Who:
                # "The Time of the Doctor" = S08E00)
                seasons = requests.get(f"https://api.themoviedb.org/3/tv/{tmdb_id}?api_key={key_}",
                                       timeout=30).json().get("number_of_seasons") or 0
                for sn in range(1, seasons + 1):
                    subs += self._search_with_retry(query=None, parent_tmdb_id=tmdb_id, season_number=sn,
                                                    episode_number=0, type="episode").data

                def assign(x):
                    if x.season_number == 0 and x.episode_number:
                        return x.episode_number
                    return (by_id.get(x.tmdb_id) if x.season_number == 0 else None) or match(x.title)

                # Was dann noch fehlt (nur lange Specials): per Titel innerhalb der Serie suchen
                found = {assign(x) for x in subs} | seen_episodes
                for e in eps:
                    if (e.get("runtime") or 0) >= 30 and e["episode_number"] not in found:
                        r = self._search_with_retry(query=e["name"], parent_tmdb_id=tmdb_id)
                        hits = [x for x in r.data if match(x.title) == e["episode_number"]]
                        if hits:
                            logger.info(f"Search S00E{e['episode_number']:02d} '{e['name']}': {len(hits)} subtitles")
                        subs += hits
                groups = {}
                for x in subs:
                    if x.ai_translated or x.machine_translated or x.foreign_parts_only:
                        continue
                    ep = assign(x)
                    if not ep:
                        logger.debug(f"Special without TMDb match skipped: {x.title}")
                        continue
                    x.season_number, x.episode_number = 0, ep
                    groups.setdefault(ep, []).append(x)
                logger.info(f"S00: {len(subs)} subtitles, {len(groups)} specials assigned")
                for ep in sorted(groups):
                    cands = sorted(groups[ep], key=lambda x: (bool(_bad.search(x.release or "")),
                                                              bool(x.hearing_impaired), -(x.download_count or 0)))
                    yield from cands[:3]

            def _all_pages(first):  # Subs-Patch: weitere Ergebnisseiten
                if season == 0 and tmdb_id:  # Specials-Patch
                    yield from _specials(first)
                    return
                if expected and tmdb_id:"""),
    ],
}

for path, reps in patches.items():
    s = path.read_text()
    if "# Specials-Patch" in s and (path.name == "engine.py" or "_specials(first)" in s):
        continue
    # erste Version dieses Patches (nur Teil 2) zuruecknehmen, dann neu anwenden
    s = s.replace("if api_season is not None and api_episode:  # Specials-Patch",
                  "if api_season and api_episode:")
    for old, new in reps:
        if s.count(old) != 1:
            sys.exit(f"Specials-Patch: Stelle in {path.name} nicht eindeutig gefunden (andere Version?)")
        s = s.replace(old, new)
    path.write_text(s)
    print(f"Specials-Patch angewendet: {path.name}")
