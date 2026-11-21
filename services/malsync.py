# Abgleich nach MyAnimeList (Teil der Trakt-Brücke, trakt-rss.py):
#  - Anime: bei Trakt gesehene Folgen/Filme -> MAL-Fortschritt. Zuordnung Trakt-Staffel -> MAL-Eintrag
#    ueber Kometa Anime-IDs (TVDB-Staffel + Folgen-Versatz) und Fribb anime-lists (TMDB-Staffel).
#  - Manga: in Komga (Bibliothek "Manga", ein Buch = ein Kapitel) gelesene Kapitel -> MAL.
#    Zuordnung ueber MAL-Link in Komga oder eindeutigen Titeltreffer der MAL-Suche, sonst von Hand.
# MAL wird nur erhoeht, nie zurueckgesetzt; "abgeschlossen" bei MAL bleibt unangetastet.
# Erst "Vorschau" (aendert nichts), dann "Jetzt abgleichen" bzw. taeglich um 05:00.
import html, json, re, secrets, threading, time, urllib.error, urllib.parse, urllib.request
from datetime import datetime

MAL_AUTH = "https://myanimelist.net/v1/oauth2"
MAL_API = "https://api.myanimelist.net/v2"
KOMGA = "http://10.0.0.5:25600"
MANGA_LIB = "Manga"
LISTS = {"fribb.json": "https://raw.githubusercontent.com/Fribb/anime-lists/master/anime-list-full.json",
         "kometa.json": "https://raw.githubusercontent.com/Kometa-Team/Anime-IDs/master/anime_ids.json"}
UA = "neotokyo-mal-sync/1.0"
HOUR = 5


def as_list(x):
    return x if isinstance(x, list) else [] if x is None else [x]


def norm(t):
    return re.sub(r"[^a-z0-9]", "", t.lower().replace("&", "and"))


class MalSync:
    def __init__(self, state, trakt_get):
        self.dir, self.f, self.trakt_get = state, state / "mal.json", trakt_get
        self.lock = threading.Lock()
        self.running = False
        self.pending = {}  # laufende MAL-Anmeldung
        threading.Thread(target=self.daily, daemon=True).start()

    def load(self):
        try:
            return json.loads(self.f.read_text())
        except (OSError, ValueError):
            return {}

    def save(self, c):
        self.f.write_text(json.dumps(c))
        self.f.chmod(0o600)

    def update(self, **kw):
        with self.lock:
            c = self.load()
            c.update(kw)
            self.save(c)

    # ---- MyAnimeList ----
    def oauth(self, form):
        req = urllib.request.Request(MAL_AUTH + "/token", urllib.parse.urlencode(form).encode(), {"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            t = json.loads(r.read())
        self.update(access_token=t["access_token"], refresh_token=t["refresh_token"],
                    expires=time.time() + t["expires_in"])

    def creds(self, c):
        d = {"client_id": c["client_id"]}
        if c.get("client_secret"):
            d["client_secret"] = c["client_secret"]
        return d

    def token(self):
        c = self.load()
        if not c.get("refresh_token"):
            raise RuntimeError("nicht mit MyAnimeList verbunden")
        if time.time() > c.get("expires", 0) - 3600:
            self.oauth(self.creds(c) | {"grant_type": "refresh_token", "refresh_token": c["refresh_token"]})
            c = self.load()
        return c["access_token"]

    def mal(self, method, path, form=None, params=None):
        url = MAL_API + path + ("?" + urllib.parse.urlencode(params) if params else "")
        req = urllib.request.Request(url, urllib.parse.urlencode(form).encode() if form is not None else None,
                                     {"Authorization": "Bearer " + self.token(), "User-Agent": UA}, method=method)
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    time.sleep(0.4)  # MAL drosselt bei zu vielen Anfragen
                    return json.loads(r.read() or b"null")
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 504) and attempt < 2:
                    time.sleep(10 * (attempt + 1)); continue
                raise
            except (TimeoutError, urllib.error.URLError):
                if attempt < 2:
                    time.sleep(10 * (attempt + 1)); continue
                raise

    def login_url(self, redirect):
        c = self.load()
        v = secrets.token_urlsafe(64)  # MAL kann nur PKCE "plain"
        st = "mal-" + secrets.token_hex(8)
        url = MAL_AUTH + "/authorize?" + urllib.parse.urlencode(
            {"response_type": "code", "client_id": c["client_id"], "code_challenge": v,
             "code_challenge_method": "plain", "state": st, "redirect_uri": redirect})
        self.pending = {"verifier": v, "state": st, "redirect": redirect, "url": url}

    def callback(self, q):
        p = self.pending
        if q.get("error"):
            self.pending = {"fehler": f"MyAnimeList meldet: {q.get('message') or q['error']}"}
        elif p.get("verifier") and q.get("code") and q.get("state") == p.get("state"):
            try:
                self.oauth(self.creds(self.load()) | {"grant_type": "authorization_code", "code": q["code"],
                                                      "code_verifier": p["verifier"], "redirect_uri": p["redirect"]})
                self.pending = {}
            except Exception as e:
                self.pending = {"fehler": f"MyAnimeList lehnt ab ({e})"}

    # ---- Komga ----
    def komga(self, path):
        req = urllib.request.Request(KOMGA + path, headers={"X-API-Key": self.load().get("komga_key", ""),
                                                            "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())

    # ---- Zuordnungstabellen ----
    def tables(self):
        for name, url in LISTS.items():
            f = self.dir / name
            if not f.exists() or time.time() - f.stat().st_mtime > 7 * 86400:
                req = urllib.request.Request(url, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=120) as r:
                    f.write_bytes(r.read())
        fribb = json.loads((self.dir / "fribb.json").read_text())
        kometa = json.loads((self.dir / "kometa.json").read_text())
        by_mal, tmdb_tv, movies, tvdb = {}, {}, {}, {}
        for e in fribb:
            m = e.get("mal_id")
            if not isinstance(m, int):
                continue
            by_mal[m] = e
            t = e.get("themoviedb_id") if isinstance(e.get("themoviedb_id"), dict) else {}
            s = (e.get("season") or {}).get("tmdb")
            if isinstance(s, int):
                for tv in as_list(t.get("tv")):
                    tmdb_tv.setdefault(tv, []).append((s, 0, m))
            for mv in as_list(t.get("movie")):
                movies[("tmdb", mv)] = m
            if e.get("type") == "MOVIE":
                for i in e.get("imdb_id") or []:
                    movies.setdefault(("imdb", i), m)
        for e in kometa.values():
            m, s = e.get("mal_id"), e.get("tvdb_season")
            if isinstance(m, int) and e.get("tvdb_id") and isinstance(s, int):
                tvdb.setdefault(e["tvdb_id"], []).append((s, e.get("tvdb_epoffset") or 0, m))
        return by_mal, tmdb_tv, movies, tvdb

    def anime_plan(self, report):
        by_mal, tmdb_tv, movies, tvdb = self.tables()
        plan = {}  # mal_id -> (Folgen, Herkunft)
        for w in self.trakt_get("/sync/watched/shows") or []:
            show, ids = w["show"], w["show"]["ids"]
            # TVDB-Staffel + Versatz (Kometa); Fribbs TMDB-Staffeln sind oft nur "1", daher nur als Notnagel
            cands = list(tvdb.get(ids.get("tvdb"), []))
            if not cands:
                cands = list(tmdb_tv.get(ids.get("tmdb"), []))
            known = bool(cands)
            cands = [x for x in set(cands) if x[0] > 0]  # Specials (0) und durchgehende Zaehlung (-1) nicht
            if not cands:
                if known:
                    report["unklar"].append(f"{show['title']}: MAL zählt durchgehend statt nach Staffeln, übersprungen")
                continue  # sonst: kein Anime
            seen = {se["number"]: {ep["number"] for ep in se.get("episodes", [])} for se in w.get("seasons", [])}
            slots = {}
            for s, off, m in cands:
                slots.setdefault((s, off), set()).add(m)
            for (s, off), ms in sorted(slots.items()):
                if len(ms) > 1:
                    report["unklar"].append(f"{show['title']} Staffel {s} ab Folge {off + 1}: mehrere MAL-Einträge "
                                            f"({', '.join(map(str, sorted(ms)))}), übersprungen")
                    continue
                nxt = min((o for (s2, o) in slots if s2 == s and o > off), default=None)
                eps = [n - off for n in seen.get(s, ()) if n > off and (nxt is None or n <= nxt)]
                if eps:
                    m = next(iter(ms))
                    if max(eps) > plan.get(m, (0,))[0]:
                        plan[m] = (max(eps), f"Trakt: {show['title']} S{s:02d}")
        for w in self.trakt_get("/sync/watched/movies") or []:
            mv = w["movie"]
            m = movies.get(("tmdb", mv["ids"].get("tmdb"))) or movies.get(("imdb", mv["ids"].get("imdb")))
            if m:
                plan[m] = (1, f"Trakt: Film {mv['title']}")
        return plan

    def manga_plan(self, report, c):
        lib = next(l["id"] for l in self.komga("/api/v1/libraries") if l["name"] == MANGA_LIB)
        series, page = [], 0
        while True:
            r = self.komga(f"/api/v1/series?library_id={lib}&read_status=READ&read_status=IN_PROGRESS&size=200&page={page}")
            series += r["content"]
            if r.get("last", True):
                break
            page += 1
        mapping, plan = c.get("manga_map", {}), {}
        for s in series:
            b = self.komga(f"/api/v1/series/{s['id']}/books?read_status=READ&sort=metadata.numberSort,desc&size=1")["content"]
            if not b:
                continue
            chap = int(b[0]["metadata"]["numberSort"])
            if chap <= 0:
                continue  # nur Kapitel 0 (Oneshot/Prolog) gelesen
            m = mapping.get(s["id"])
            if m is None:
                for l in s["metadata"].get("links") or []:
                    if (x := re.search(r"myanimelist\.net/manga/(\d+)", l.get("url", ""))):
                        m = int(x.group(1))
            if m is None:
                m, hint = self.find_manga(s["metadata"].get("title") or s["name"])
                if m:
                    mapping[s["id"]] = m
                else:
                    report["offen"].append({"id": s["id"], "name": s["name"], "kapitel": chap, "vorschlag": hint})
                    continue
            if m and chap > 0 and chap > plan.get(m, (0,))[0]:
                plan[m] = (chap, f"Komga: {s['name']}")
        self.update(manga_map=mapping)
        return plan

    def find_manga(self, name):
        keys = {norm(name), norm(re.sub(r"\(.*?\)", "", name))}
        q = re.sub(r"\(.*?\)", "", name).strip()[:60]
        if len(q) < 3:
            return None, []
        res = self.mal("GET", "/manga", params={"q": q, "limit": 10, "nsfw": "true",
                                                        "fields": "alternative_titles,media_type"})
        hits, hint = set(), []
        for d in (res or {}).get("data", []):
            n = d["node"]
            if n.get("media_type") in ("light_novel", "novel"):
                continue
            alt = n.get("alternative_titles") or {}
            titles = [n["title"], alt.get("en", ""), alt.get("ja", "")] + (alt.get("synonyms") or [])
            if any(norm(t) in keys for t in titles if t):
                hits.add(n["id"])
            if len(hint) < 3:
                hint.append(f"{n['title']} ({n['id']})")
        return (hits.pop() if len(hits) == 1 else None), hint

    # ---- Abgleich ----
    def apply(self, kind, plan, ignore, report, dry):
        unit, field, done = ("Folgen", "num_watched_episodes", "watching") if kind == "anime" else \
            ("Kapitel", "num_chapters_read", "reading")
        total = "num_episodes" if kind == "anime" else "num_chapters"
        report.setdefault("geprueft", {})[kind] = len(plan)
        for m, (n, src) in sorted(plan.items()):
            if f"{kind}:{m}" in ignore:
                continue
            try:
                info = self.mal("GET", f"/{kind}/{m}", params={"fields": f"{total},my_list_status"})
                cap = info.get(total) or 0
                n = min(n, cap) if cap else n
                st = info.get("my_list_status") or {}
                have = st.get(field.replace("num_watched_episodes", "num_episodes_watched"), 0)
                if st.get("status") == "completed" or have >= n:
                    continue
                status = "completed" if cap and n >= cap else done
                if not dry:
                    self.mal("PATCH", f"/{kind}/{m}/my_list_status", {"status": status, field: n})
                report["aenderungen"].append({"art": kind, "mal": m, "titel": info.get("title", ""), "von": have,
                                              "auf": n, "einheit": unit, "status": status, "quelle": src})
            except Exception as e:
                report["fehler"].append(f"{src} (MAL {m}): {e}")

    def run(self, dry):
        if self.running:
            return
        self.running = True
        report = {"zeit": datetime.now().strftime("%d.%m.%Y %H:%M"), "vorschau": dry,
                  "aenderungen": [], "offen": [], "unklar": [], "fehler": []}
        try:
            c = self.load()
            ignore = set(c.get("ignore", "").split())
            try:
                self.apply("anime", self.anime_plan(report), ignore, report, dry)
            except Exception as e:
                report["fehler"].append(f"Anime/Trakt: {e}")
            if c.get("komga_key"):
                try:
                    self.apply("manga", self.manga_plan(report, c), ignore, report, dry)
                except Exception as e:
                    report["fehler"].append(f"Manga/Komga: {e}")
            else:
                report["fehler"].append("Komga: kein API-Key hinterlegt, Manga übersprungen")
        finally:
            self.update(report=report, **({} if dry else {"last_run": datetime.now().strftime("%Y-%m-%d")}))
            self.running = False

    def daily(self):
        while True:
            time.sleep(300)
            c = self.load()
            now = datetime.now()
            if c.get("active") and now.hour >= HOUR and c.get("last_run") != now.strftime("%Y-%m-%d"):
                try:
                    self.run(False)
                except Exception:
                    pass

    # ---- Seite ----
    def page(self, redirect):
        c, p, e = self.load(), self.pending, html.escape
        out = ["<h2>MyAnimeList-Abgleich</h2>"]
        if p.get("fehler"):
            out.append(f"<p>⚠️ {e(p['fehler'])}</p>")
        if p.get("verifier"):
            out.append(f'<div class="box"><a href="{e(p["url"])}" rel="noreferrer">Bei MyAnimeList anmelden</a> '
                       'und Zugriff erlauben, danach geht es automatisch hierher zurück.</div>')
        elif not c.get("refresh_token"):
            out.append('<form method="post" action="/mal/app"><p>1. Auf <a href="https://myanimelist.net/apiconfig">'
                       'myanimelist.net/apiconfig</a> „Create ID“: App Type <b>other</b>, App Redirect URL '
                       f'<code>{e(redirect)}</code>, Homepage beliebig.<br>2. Client ID hier eintragen '
                       '(Secret nur bei App Type „web“):</p>'
                       f'<input name="client_id" placeholder="Client ID" value="{e(c.get("client_id", ""))}">'
                       '<input name="client_secret" placeholder="Client Secret (optional)" type="password">'
                       '<button>Bei MyAnimeList anmelden</button></form>')
            return "".join(out)
        else:
            out.append("<p>✅ Mit MyAnimeList verbunden. Komga: "
                       + ("✅ API-Key hinterlegt" if c.get("komga_key") else "⚠️ kein API-Key") + "</p>")
        if not c.get("refresh_token"):
            return "".join(out)
        aktiv = c.get("active")
        out.append('<form method="post" action="/mal/run" style="display:inline"><input type="hidden" name="dry" value="1">'
                   '<button>Vorschau</button></form> '
                   '<form method="post" action="/mal/run" style="display:inline"><button>Jetzt abgleichen</button></form> '
                   '<form method="post" action="/mal/active" style="display:inline"><button>'
                   + ("Täglich: an (ausschalten)" if aktiv else "Täglich 05:00 einschalten") + '</button></form>')
        if self.running:
            out.append("<p>⏳ Abgleich läuft … Seite in einer Minute neu laden.</p>")
        r = c.get("report")
        if r:
            out.append(f'<h3>{"Vorschau" if r["vorschau"] else "Abgleich"} vom {e(r["zeit"])}</h3>')
            if r["aenderungen"]:
                verb = "würde setzen" if r["vorschau"] else "gesetzt"
                out.append(f"<p>{len(r['aenderungen'])} Einträge ({verb}):</p><table>")
                for a in r["aenderungen"]:
                    out.append(f'<tr><td><a href="https://myanimelist.net/{a["art"]}/{a["mal"]}">{e(a["titel"])}</a>'
                               f'<br><small>{e(a["quelle"])}</small></td><td>{a["von"]} → {a["auf"]} {a["einheit"]}'
                               f'{" ✓" if a["status"] == "completed" else ""}</td></tr>')
                out.append("</table>")
            else:
                out.append("<p>Nichts zu ändern, MAL ist schon aktuell.</p>")
            g = r.get("geprueft", {})
            if g:
                out.append(f"<p><small>Zugeordnet: {g.get('anime', 0)} Anime-Einträge (Trakt), "
                           f"{g.get('manga', 0)} Manga (Komga)</small></p>")
            if r["offen"]:
                out.append("<h3>Manga ohne Zuordnung</h3><p>MAL-ID eintragen (Zahl aus der MAL-Adresse), "
                           "0 = nicht abgleichen:</p>")
                for o in r["offen"]:
                    out.append(f'<form method="post" action="/mal/map" class="row"><b>{e(o["name"])}</b> '
                               f'<small>(bis Kapitel {o["kapitel"]}; MAL-Suche: {e(", ".join(o["vorschlag"]) or "nichts")})'
                               f'</small><input type="hidden" name="id" value="{e(o["id"])}">'
                               '<input name="mal" placeholder="MAL-ID" inputmode="numeric"><button>Speichern</button></form>')
            for k, t in (("unklar", "Übersprungen"), ("fehler", "Fehler")):
                if r[k]:
                    out.append(f"<h3>{t}</h3><ul>" + "".join(f"<li>{e(x)}</li>" for x in r[k]) + "</ul>")
        out.append('<form method="post" action="/mal/ignore"><p>Nie abgleichen (z.B. <code>anime:1535 manga:2</code>):</p>'
                   f'<input name="ignore" value="{e(c.get("ignore", ""))}"><button>Speichern</button></form>')
        return "".join(out)

    def post(self, path, form, redirect):
        if path == "/mal/app" and form.get("client_id"):
            self.update(client_id=form["client_id"], client_secret=form.get("client_secret", ""))
            self.login_url(redirect)
        elif path == "/mal/run":
            threading.Thread(target=self.run, args=(bool(form.get("dry")),), daemon=True).start()
            time.sleep(1)
        elif path == "/mal/active":
            self.update(active=not self.load().get("active"))
        elif path == "/mal/map" and form.get("id") and form.get("mal", "").isdigit():
            with self.lock:
                c = self.load()
                c.setdefault("manga_map", {})[form["id"]] = int(form["mal"]) or 0
                if c.get("report"):
                    c["report"]["offen"] = [o for o in c["report"]["offen"] if o["id"] != form["id"]]
                self.save(c)
        elif path == "/mal/ignore":
            self.update(ignore=form.get("ignore", ""))
        elif path == "/mal/komga" and form.get("key"):
            self.update(komga_key=form["key"])
