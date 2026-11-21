# Trakt-Kalender als RSS-Feed (Trakt bietet Feeds nur mit VIP). Holt ueber die kostenlose
# Trakt-API die Folgen der eigenen Serien und die eigenen Filmstarts.
# GET /             Einrichtung: Client-ID der Trakt-API-App, Anmeldung per PKCE (Code von Trakt
#                   einfuegen) oder, falls die App ein Secret hat, per Geraetecode
# GET /neu.xml      erschienen in den letzten 14 Tagen (Eintrag erscheint, sobald die Folge raus ist)
# GET /bald.xml     kommt in den naechsten 30 Tagen
#                   ?nur=serien bzw. ?nur=filme filtert (z.B. /neu.xml?nur=filme)
# Zugangsdaten und Tokens liegen im State-Verzeichnis. Aufruf: trakt-rss <port> <state-dir>
import base64, hashlib, html, json, secrets, sys, threading, time, urllib.error, urllib.parse, urllib.request
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from malsync import MalSync

PORT, STATE = int(sys.argv[1]), Path(sys.argv[2])
# Trakt nimmt nur https-Ruecksprungadressen: Adresse auf dem VPS, die per 302 an /callback hier weiterleitet
REDIRECT = sys.argv[3] if len(sys.argv) > 3 else None
CFG = STATE / "trakt.json"  # client_id, client_secret, access_token, refresh_token, expires
API = "https://api.trakt.tv"
OOB = "urn:ietf:wg:oauth:2.0:oob"
lock = threading.Lock()
pending = {}  # laufende Geraete-Anmeldung
cache = {}  # Feed -> (Zeit, XML)


def load():
    try:
        return json.loads(CFG.read_text())
    except (OSError, ValueError):
        return {}


def save(c):
    CFG.write_text(json.dumps(c))
    CFG.chmod(0o600)


def call(path, body=None, token=None, c=None):
    c = c or load()
    h = {"Content-Type": "application/json", "trakt-api-version": "2", "trakt-api-key": c.get("client_id", ""),
         "User-Agent": "neotokyo-trakt-rss/1.0"}
    if token:
        h["Authorization"] = "Bearer " + token
    req = urllib.request.Request(API + path, json.dumps(body).encode() if body is not None else None, h)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or b"null")


def token():
    with lock:
        c = load()
        if not c.get("refresh_token"):
            raise RuntimeError("nicht mit Trakt verbunden")
        if time.time() > c.get("expires", 0) - 3600:
            body = {"refresh_token": c["refresh_token"], "client_id": c["client_id"],
                    "grant_type": "refresh_token", "redirect_uri": c.get("redirect_uri", OOB)}
            if c.get("client_secret"):
                body["client_secret"] = c["client_secret"]
            t = call("/oauth/token", body, c=c)
            c.update(access_token=t["access_token"], refresh_token=t["refresh_token"],
                     expires=t["created_at"] + t["expires_in"])
            save(c)
        return c["access_token"]


def poll_device(code, interval, until):
    c = load()
    while time.time() < until:
        time.sleep(interval)
        try:
            t = call("/oauth/device/token", {"code": code, "client_id": c["client_id"],
                                             "client_secret": c["client_secret"]}, c=c)
        except urllib.error.HTTPError as e:
            if e.code == 400:  # wartet noch auf Bestaetigung
                continue
            if e.code == 429:
                interval += 1; continue
            pending["fehler"] = f"Trakt meldet {e.code}"
            break
        c.update(access_token=t["access_token"], refresh_token=t["refresh_token"],
                 expires=t["created_at"] + t["expires_in"])
        save(c)
        pending.clear()
        return
    pending["fehler"] = pending.get("fehler") or "Code abgelaufen, bitte neu verbinden"


def items(kind):
    now = datetime.now(timezone.utc)
    start, days = (now - timedelta(days=14), 15) if kind == "neu" else (now, 31)
    tok, d = token(), start.strftime("%Y-%m-%d")
    out = []
    for e in call(f"/calendars/my/shows/{d}/{days}", token=tok) or []:
        s, ep = e["show"], e["episode"]
        when = datetime.fromisoformat(e["first_aired"].replace("Z", "+00:00"))
        if (kind == "neu") != (when <= now):
            continue
        title = f"{s['title']} S{ep['season']:02d}E{ep['number']:02d}" + (f" – {ep['title']}" if ep.get("title") else "")
        link = f"https://trakt.tv/shows/{s['ids']['slug']}/seasons/{ep['season']}/episodes/{ep['number']}"
        out.append((when, title, link, f"trakt-ep-{ep['ids']['trakt']}", "Folge"))
    for e in call(f"/calendars/my/movies/{d}/{days}", token=tok) or []:
        m = e["movie"]
        when = datetime.fromisoformat(e["released"] + "T00:00:00+00:00")
        if (kind == "neu") != (when <= now):
            continue
        out.append((when, f"Film: {m['title']} ({m.get('year') or ''})", f"https://trakt.tv/movies/{m['ids']['slug']}",
                    f"trakt-movie-{m['ids']['trakt']}-{e['released']}", "Film"))
    return sorted(out, reverse=(kind == "neu"))


def feed(kind, nur=None):
    # nur="serien" oder "filme" filtert, sonst beides
    hit = cache.get((kind, nur))
    if hit and time.time() - hit[0] < 1800:
        return hit[1]
    name = ("Trakt: neu erschienen" if kind == "neu" else "Trakt: demnächst") + \
        {"serien": " (Serien)", "filme": " (Filme)"}.get(nur, "")
    rows = []
    for when, title, link, guid, cat in items(kind):
        if (nur == "serien" and cat != "Folge") or (nur == "filme" and cat != "Film"):
            continue
        datum = when.astimezone().strftime("%d.%m.%Y %H:%M")
        rows.append(f"<item><title>{html.escape(title)}</title><link>{html.escape(link)}</link>"
                    f"<guid isPermaLink=\"false\">{guid}</guid><category>{cat}</category>"
                    f"<pubDate>{format_datetime(when)}</pubDate>"
                    f"<description>{html.escape(cat + ', ' + datum)}</description></item>")
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<rss version="2.0"><channel>'
           f"<title>{name}</title><link>https://trakt.tv/calendars/my/shows</link>"
           f"<description>{name}</description>{''.join(rows)}</channel></rss>")
    cache[(kind, nur)] = (time.time(), xml)
    return xml


PAGE = """<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Trakt-RSS</title>
<style>body{{font:16px system-ui,sans-serif;max-width:560px;margin:auto;padding:16px;background:#f5f5f7;color:#1d1d1f}}
@media (prefers-color-scheme:dark){{body{{background:#000;color:#f5f5f7}}input{{background:#1c1c1e;color:#f5f5f7}}}}
input{{width:100%;box-sizing:border-box;padding:9px;margin:4px 0 10px;border-radius:8px;border:1px solid #888;font:inherit}}
button{{padding:9px 16px;border:0;border-radius:8px;background:#ed1c24;color:#fff;font:inherit;font-weight:600}}
table{{border-collapse:collapse;width:100%}} td{{padding:6px 4px;border-bottom:1px solid rgba(127,127,127,.3);vertical-align:top}}
.row{{margin:10px 0}} code{{word-break:break-all}} .box{{padding:12px;border-radius:10px;background:rgba(127,127,127,.15);margin:12px 0}}</style></head><body>
<h1>Trakt-RSS</h1>{body}</body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="text/html; charset=utf-8"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def exchange(self, code):
        # Code von Trakt gegen Tokens tauschen (PKCE)
        c = load()
        try:
            t = call("/oauth/token", {"code": code, "client_id": c["client_id"], "redirect_uri": pending["redirect"],
                                      "grant_type": "authorization_code", "code_verifier": pending["verifier"]}, c=c)
            c.update(access_token=t["access_token"], refresh_token=t["refresh_token"],
                     expires=t["created_at"] + t["expires_in"], redirect_uri=pending["redirect"])
            save(c)
            pending.clear()
            cache.clear()
        except Exception as e:
            pending["fehler"] = f"Code abgelehnt ({e}), nochmal bei Trakt anmelden"

    def do_GET(self):
        if self.path.startswith("/callback"):
            q = {k: v[0] for k, v in urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).items()}
            if q.get("state", "").startswith("mal-"):
                mal.callback(q)
            elif pending.get("verifier") and q.get("code") and q.get("state") == pending.get("state"):
                self.exchange(q["code"])
            elif q.get("error"):
                pending["fehler"] = f"Trakt meldet: {q.get('error_description') or q['error']}"
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return
        path = urllib.parse.urlsplit(self.path).path
        if path in ("/neu.xml", "/bald.xml"):
            try:
                nur = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("nur", [None])[0]
                return self.send(200, feed(path[1:-4], nur), "application/rss+xml; charset=utf-8")
            except Exception as e:
                # 502 statt 503: bei 503 sperrt FreshRSS den Feed fuer 25 Minuten
                return self.send(502, f"Fehler: {e}", "text/plain; charset=utf-8")
        if self.path != "/":
            return self.send(404, "nicht gefunden", "text/plain")
        c = load()
        host = self.headers.get("Host", f"10.0.0.5:{PORT}")
        if pending.get("pkce_url"):
            u = html.escape(pending["pkce_url"])
            body = (f'<div class="box">1. <a href="{u}" rel="noreferrer">Bei Trakt anmelden</a> '
                    'und Zugriff erlauben. Öffnet sich stattdessen die Trakt-App oder lädt nichts, diesen Link '
                    f'kopieren und im Browser (z.B. am PC) öffnen:<br><code>{u}</code><br>'
                    '2. Den Code, den Trakt danach anzeigt, hier einfügen:</div>'
                    '<form method="post" action="/code"><input name="code" placeholder="Code von Trakt" autocomplete="off">'
                    '<button>Verbinden</button></form>')
        elif pending.get("user_code"):
            body = (f'<div class="box">Öffne <a href="{pending["url"]}" target="_blank">{pending["url"]}</a> '
                    f'und gib diesen Code ein:<h2>{pending["user_code"]}</h2>Danach diese Seite neu laden.</div>')
        elif c.get("refresh_token"):
            body = (f'<p>✅ Mit Trakt verbunden.</p><div class="box">Feeds für FreshRSS:<br>'
                    f'<code>http://{host}/neu.xml</code> – erschienen (letzte 14 Tage)<br>'
                    f'<code>http://{host}/bald.xml</code> – demnächst (30 Tage)<br>'
                    'Nur Serien oder nur Filme: <code>?nur=serien</code> bzw. <code>?nur=filme</code> anhängen</div>'
                    '<form method="post" action="/verbinden"><button>Neu verbinden</button></form>')
        else:
            body = ""
        if pending.get("fehler"):
            body += f'<p>⚠️ {html.escape(pending["fehler"])}</p>'
        if not c.get("refresh_token") and not pending.get("user_code") and not pending.get("pkce_url"):
            body += ('<form method="post" action="/app"><p>1. Auf <a href="https://trakt.tv/oauth/applications/new" '
                     'target="_blank">trakt.tv/oauth/applications/new</a> eine App anlegen (Name beliebig, '
                     f'Redirect URI <code>{REDIRECT or "http://" + host + "/callback"}</code>).<br>2. Client ID hier eintragen '
                     '(Secret nur, falls Trakt eins anzeigt):</p>'
                     f'<input name="client_id" placeholder="Client ID" value="{html.escape(c.get("client_id", ""))}">'
                     '<input name="client_secret" placeholder="Client Secret (optional)" type="password">'
                     '<button>Speichern und verbinden</button></form>')
        if c.get("refresh_token"):
            body += mal.page(self.redirect())
        self.send(200, PAGE.format(body=body))

    def redirect(self):
        return REDIRECT or f"http://{self.headers.get('Host', f'10.0.0.5:{PORT}')}/callback"

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        form = {k: v[0].strip() for k, v in urllib.parse.parse_qs(self.rfile.read(n).decode()).items()}
        if self.path.startswith("/mal/"):
            mal.post(self.path, form, self.redirect())
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return
        c = load()
        if self.path == "/app" and form.get("client_id"):
            c["client_id"] = form["client_id"]
            c["client_secret"] = form.get("client_secret", "")
            save(c)
        if self.path == "/code" and pending.get("verifier") and form.get("code"):
            self.exchange(form["code"])
        elif self.path in ("/app", "/verbinden") and c.get("client_id") and not c.get("client_secret"):
            # PKCE: kein Secret, stattdessen Pruefschluessel
            pending.clear()
            v = secrets.token_urlsafe(64)
            ch = base64.urlsafe_b64encode(hashlib.sha256(v.encode()).digest()).rstrip(b"=").decode()
            # Trakt leitet nach der Anmeldung zurueck auf /callback dieser Seite
            redir = self.redirect()
            st = secrets.token_hex(8)
            q = urllib.parse.urlencode({"response_type": "code", "client_id": c["client_id"], "redirect_uri": redir,
                                        "code_challenge": ch, "code_challenge_method": "S256", "state": st})
            pending.update(verifier=v, redirect=redir, state=st, pkce_url="https://trakt.tv/oauth/authorize?" + q)
        elif self.path in ("/app", "/verbinden") and c.get("client_id") and c.get("client_secret"):
            pending.clear()
            try:
                d = call("/oauth/device/code", {"client_id": c["client_id"]}, c=c)
                pending.update(user_code=d["user_code"], url=d["verification_url"])
                threading.Thread(target=poll_device, args=(d["device_code"], d["interval"], time.time() + d["expires_in"]),
                                 daemon=True).start()
            except Exception as e:
                pending["fehler"] = f"Trakt lehnt die App ab ({e}), Client ID/Secret prüfen"
        self.send_response(303)
        self.send_header("Location", "/")
        self.end_headers()


mal = MalSync(STATE, lambda path: call(path, token=token()))
ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
