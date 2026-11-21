# Patch fuer mkv-episode-matcher 1.3.6 (wird nach pip install angewendet, siehe episode-matcher.nix):
# 1. Die Untertitelsuche nimmt nur die erste Ergebnisseite von OpenSubtitles (50 Treffer). Bei
#    beliebten Serien verteilen die sich auf wenige Folgen (Friends S01: 7 von 24). Jetzt wird
#    weitergeblaettert, bis jede Folge laut TMDb einen Untertitel hat (hoechstens 20 Seiten).
# 2. Liegen schon >= 3 Untertitel im Cache, wurde nichts mehr nachgeladen, fehlende Folgen blieben
#    fuer immer fehlend. Jetzt werden nur die fehlenden geladen (schont das Download-Limit).
# 3. Beim Download-Limit nicht stundenlang weiterprobieren (siehe unten).
# 4. Suche aus der Weboberflaeche (Hintergrund-Thread) ging nie (siehe unten).
# 5. Abgelaufene Anmeldung (24 h) erneuern (siehe unten).
# 6. Suche immer ueber die TMDb-ID (die Oberflaeche gab keine mit, die Textsuche fand fuer Doctor
#    Who S02 nur 4 Folgen), fehlende Folgen einzeln nachsuchen, nur Folgen 1..N laden.
# 7. Beim Download-Limit keine Wiederholungen (siehe unten).
# 8. Pro Folge den besten Untertitel waehlen statt den ersten Treffer (siehe unten).
import sys
from pathlib import Path

p = Path(sys.argv[1]) / "mkv_episode_matcher/core/providers/subtitles.py"
s = p.read_text()
if "# Subs-Patch" in s:
    sys.exit(0)


def rep(old, new):
    global s
    if s.count(old) != 1:
        sys.exit(f"Subs-Patch: Stelle nicht eindeutig gefunden (andere Version?):\n{old[:80]}")
    s = s.replace(old, new)


rep('''        season_number: int | None = None,
        type: str | None = None,
    ):
        """Search for subtitles with retry logic."""''', '''        season_number: int | None = None,
        type: str | None = None,
        page: int | None = None,  # Subs-Patch
        episode_number: int | None = None,
    ):
        """Search for subtitles with retry logic."""''')
rep('''                season_number=season_number,
                type=type,
            )''', '''                season_number=season_number,
                type=type,
                page=page,
                episode_number=episode_number,
            )''')
rep('''        downloaded_subtitles = []

        try:''', '''        downloaded_subtitles = []

        # Subs-Patch: vorhandene Folgen nicht neu laden; Zahl der Folgen von TMDb
        import re as _re
        cached_eps = set()
        for f in cache_dir.glob(f"{show_name} - S{season:02d}E*.srt"):
            m_ = _re.search(r"E(\\d+)\\.srt$", f.name)
            if m_:
                cached_eps.add(int(m_.group(1)))
        expected = 0
        try:
            from mkv_episode_matcher.tmdb_client import fetch_season_details, fetch_show_id

            sid = tmdb_id or fetch_show_id(search_show_name)
            if sid:
                expected = fetch_season_details(str(sid), season)
                # Suche ueber die TMDb-ID statt per Text (Oberflaeche gibt keine ID mit)
                tmdb_id = tmdb_id or int(sid)
        except Exception as e:
            logger.warning(f"Episode count from TMDb unavailable: {e}")
        if expected and len(cached_eps) >= expected:
            logger.info(f"All {expected} episodes of S{season:02d} cached, no download")
            return []
        logger.info(f"S{season:02d}: {expected or '?'} episodes, {len(cached_eps)} cached")

        try:''')
rep('''            seen_episodes = set()
''', '''            seen_episodes = set(cached_eps)

            def _all_pages(first):  # Subs-Patch: weitere Ergebnisseiten
                yield from first.data
                total = getattr(first, "total_pages", 1) or 1
                for pg in range(2, min(total, 20) + 1):
                    if expected and len(seen_episodes) >= expected:
                        return
                    if tmdb_id:
                        r = self._search_with_retry(query=None, parent_tmdb_id=tmdb_id,
                                                    season_number=season, type="episode", page=pg)
                    else:
                        r = self._search_with_retry(query=f"{search_show_name} S{season:02d}",
                                                    type="episode", page=pg)
                    logger.info(f"Search page {pg}/{total}: {len(r.data)} subtitles")
                    yield from r.data
                # fehlende Folgen einzeln suchen
                if expected and tmdb_id:
                    for ep in range(1, expected + 1):
                        if ep in seen_episodes:
                            continue
                        r = self._search_with_retry(query=None, parent_tmdb_id=tmdb_id, season_number=season,
                                                    type="episode", episode_number=ep)
                        logger.info(f"Search S{season:02d}E{ep:02d}: {len(r.data)} subtitles")
                        yield from r.data[:5]
''')
rep('''            for subtitle in response.data:
''', '''            for subtitle in _all_pages(response):
''')
# nur Folgen 1..N der Staffel laden (TMDb-Zahl), falsch eingetragene E00/E26 kosten sonst Limit
rep('''                if ep_num in seen_episodes:
                    continue
''', '''                if expected and not 1 <= ep_num <= expected:  # Subs-Patch
                    continue
                if ep_num in seen_episodes:
                    continue
''')
# 3. Download-Limit erreicht: die Bibliothek wirft "Download limit reached" bzw. HTTP 406, das
#    Programm versuchte es dann 6x mit Pausen (~1,5 min) und machte mit dem naechsten Kandidaten
#    weiter, mit allen Ergebnisseiten stundenlang. Jetzt: sofort aufhoeren zu laden.
rep('''                except Exception as e:
                    logger.error(f"Failed to download/save subtitle: {e}")
''', '''                except Exception as e:
                    logger.error(f"Failed to download/save subtitle: {e}")
                    if "limit" in str(e).lower() or "406" in str(e):  # Subs-Patch
                        logger.warning("OpenSubtitles download limit reached, no more downloads today")
                        break
''')
rep('''                # Return early if we have enough cached subtitles
                if (
                    len(provider_results) >= 3
                ):  # Arbitrary threshold for "enough" episodes
                    logger.info("Using cached subtitles, skipping download")
                    return results
            else:
                # For non-local providers, only use if we don't have cached results
                if not results:
                    logger.info(f"No cached subtitles found, trying provider {i + 1}")
                    results.extend(provider_results)
                else:
                    logger.info(
                        "Skipping additional providers since cached subtitles are available"
                    )
                    break
''', '''            else:
                # Subs-Patch: fehlende Folgen ergaenzen (der Provider laedt nur, was nicht im Cache ist)
                have = {x.episode_info.episode for x in results}
                results.extend(x for x in provider_results if x.episode_info.episode not in have)
''')
# 4. Die Weboberflaeche sucht in einem Hintergrund-Thread; signal.alarm (Zeitlimit) geht nur im
#    Haupt-Thread, jede Suche scheiterte mit "signal only works in main thread". Zeitlimit
#    nur im Haupt-Thread setzen (die Anfragen haben ohnehin eigene Timeouts).
old_sig = 'if hasattr(signal, "SIGALRM"):'
if s.count(old_sig) != 4:
    sys.exit("Subs-Patch: signal.alarm-Stellen nicht wie erwartet (andere Version?)")
s = s.replace(old_sig, 'if hasattr(signal, "SIGALRM") and __import__("threading").current_thread() is __import__("threading").main_thread():  # Subs-Patch')
# 5. Die Anmeldung bei OpenSubtitles passiert nur beim Start, das Token gilt 24 h. Danach
#    scheiterte jeder Download mit "401 invalid token" (6 Versuche je Untertitel). Bei 401 einmal
#    neu anmelden und den Download wiederholen.
rep('''        try:
            return self.client.download_and_save(subtitle)
        finally:''', '''        try:
            try:
                return self.client.download_and_save(subtitle)
            except Exception as e:  # Subs-Patch: abgelaufene Anmeldung erneuern
                if "401" not in str(e):
                    raise
                logger.warning("OpenSubtitles token expired, logging in again")
                self._authenticate()
                return self.client.download_and_save(subtitle)
        finally:''')
# 7. Beim Download-Limit nicht wiederholen: retry_with_backoff versuchte es 6x mit Pausen
#    (~1,5 min Wartezeit bei jedem Scan), obwohl das Limit erst nach Stunden zurueckgesetzt wird.
rep('''                except Exception as e:
                    last_exception = e
                    if attempt == max_retries:''', '''                except Exception as e:
                    last_exception = e
                    if "limit" in str(e).lower() or " 406" in str(e):  # Subs-Patch
                        raise
                    if attempt == max_retries:''')
# 8. Mit TMDb-ID jede fehlende Folge einzeln suchen und den besten Untertitel nehmen. Vorher nahm das
#    Programm den ersten Treffer, und OpenSubtitles fuehrt unter einer Folge auch falsch
#    hochgeladene Dateien (Doctor Who S02: "Best Of Specials", Confidential, alte Serie). 7 von 13
#    Untertiteln gehoerten zu anderen Folgen, kein Treffer moeglich. Jetzt: maschinell uebersetzte
#    und offensichtliche Extras aussortieren, ohne Hoergeschaedigten-Zeilen bevorzugen, dann die
#    meistgeladene Datei (bis zu 3 Kandidaten, falls ein Download scheitert).
rep('''            def _all_pages(first):  # Subs-Patch: weitere Ergebnisseiten
                yield from first.data
''', '''            _bad = _re.compile(r"confiden|extras?\\b|best.?of|special|commentary|making.?of|behind.?the", _re.I)

            def _best_per_episode():  # Subs-Patch 8
                for ep in range(1, expected + 1):
                    if ep in seen_episodes:
                        continue
                    r = self._search_with_retry(query=None, parent_tmdb_id=tmdb_id, season_number=season,
                                                type="episode", episode_number=ep)
                    cands = [x for x in r.data
                             if not (x.ai_translated or x.machine_translated or x.foreign_parts_only)
                             and x.season_number in (None, season) and x.episode_number in (None, ep)]
                    cands.sort(key=lambda x: (bool(_bad.search(x.release or "")), bool(x.hearing_impaired),
                                              -(x.download_count or 0)))
                    best = cands[0].release if cands else "-"
                    logger.info(f"Search S{season:02d}E{ep:02d}: {len(r.data)} subtitles, best: {best}")
                    yield from cands[:3]

            def _all_pages(first):  # Subs-Patch: weitere Ergebnisseiten
                if expected and tmdb_id:
                    yield from _best_per_episode()
                    return
                yield from first.data
''')
p.write_text(s)
print("Subs-Patch angewendet")
