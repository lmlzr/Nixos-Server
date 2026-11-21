# Steuerseite fuer die Bitcoin-"Lotterie" (Solo-Mining mit cpuminer ueber solo.ckpool.org).
# GET /            Seite mit Status, Wallet-Adresse, Start/Stopp
# GET /api/status  JSON fuer das Homepage-Widget
# POST /start, /stop, /address (Formular)
# POST /threads   Anzahl Threads (1..max)
# Adresse, Threads und ob der Miner laufen soll liegen im State-Verzeichnis, nach einem Neustart
# laeuft er so weiter wie vorher. Aufruf: btc-lottery <cpuminer> <port> <state-dir> <max-threads>
import html, json, re, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs

CPUMINER, PORT, STATE, MAX_THREADS = sys.argv[1], int(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4])
POOL = "stratum+tcp://solo.ckpool.org:3333"
ADDR_FILE, RUN_FILE, THREADS_FILE = STATE / "address", STATE / "running", STATE / "threads"
ADDR_RE = re.compile(r"^(bc1[0-9a-z]{25,87}|[13][1-9A-HJ-NP-Za-km-z]{25,34})$")

lock = threading.Lock()
proc = None
stats = {"hashrate_khs": 0.0, "accepted": 0, "rejected": 0, "started": None, "last": ""}


def address():
    return ADDR_FILE.read_text().strip() if ADDR_FILE.exists() else ""


def threads():
    try:
        return min(max(int(THREADS_FILE.read_text()), 1), MAX_THREADS)
    except (OSError, ValueError):
        return 1


def reader(p):
    for line in p.stdout:
        line = line.strip()
        if m := re.search(r"([\d.]+) khash/s", line):
            stats["hashrate_khs"] = float(m.group(1))
        if m := re.search(r"accepted: (\d+)/(\d+)", line):
            stats["accepted"], stats["rejected"] = int(m.group(1)), int(m.group(2)) - int(m.group(1))
        stats["last"] = line[-200:]


def start():
    global proc
    with lock:
        if proc and proc.poll() is None or not address():
            return
        proc = subprocess.Popen(
            [CPUMINER, "-a", "sha256d", "-o", POOL, "-u", address(), "-p", "x", "-t", str(threads())],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        stats.update(hashrate_khs=0.0, accepted=0, rejected=0, started=time.time(), last="")
        threading.Thread(target=reader, args=(proc,), daemon=True).start()
        RUN_FILE.touch()


def stop():
    global proc
    with lock:
        RUN_FILE.unlink(missing_ok=True)
        if proc and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(10)
            except subprocess.TimeoutExpired:
                proc.kill()
        proc = None
        stats.update(hashrate_khs=0.0, started=None)


def status():
    running = bool(proc and proc.poll() is None)
    a = address()
    return {
        "running": running,
        "status": "läuft" if running else "aus",
        "hashrate": f"{stats['hashrate_khs'] / 1000:.2f} MH/s" if running else "-",
        "hashrate_khs": stats["hashrate_khs"] if running else 0,
        "accepted": stats["accepted"],
        "uptime_h": round((time.time() - stats["started"]) / 3600, 1) if running and stats["started"] else 0,
        "threads": threads(),
        "watt": f"~{10 + 5 * threads()} W" if running else "0 W",
        "address": a,
        "pool_stats": f"https://solo.ckpool.org/users/{a}" if a else "",
        "last": stats["last"],
    }


PAGE = """<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>BTC-Lotterie</title>
<style>
:root{{--bg:#f5f5f7;--card:#fff;--fg:#1d1d1f;--mut:#6e6e73;--acc:#f7931a;--bad:#d70015}}
@media (prefers-color-scheme:dark){{:root{{--bg:#000;--card:#1c1c1e;--fg:#f5f5f7;--mut:#98989d}}}}
body{{background:var(--bg);color:var(--fg);font:16px system-ui,sans-serif;margin:0;padding:16px}}
main{{max-width:520px;margin:auto;background:var(--card);border-radius:14px;padding:20px}}
h1{{margin:0 0 4px;font-size:22px}} .mut{{color:var(--mut);font-size:14px}}
dl{{display:grid;grid-template-columns:auto 1fr;gap:6px 16px;margin:18px 0}} dt{{color:var(--mut)}} dd{{margin:0;word-break:break-all}}
input,select{{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid var(--mut);background:var(--bg);color:var(--fg);font:inherit}}
button{{padding:10px 18px;border:0;border-radius:8px;font:inherit;font-weight:600;color:#fff;background:var(--acc);cursor:pointer;margin-top:10px}}
button.stop{{background:var(--bad)}} a{{color:var(--acc)}} pre{{white-space:pre-wrap;font-size:12px;color:var(--mut)}}
</style></head><body><main>
<h1>BTC-Lotterie</h1><div class="mut">Solo-Mining über solo.ckpool.org. Trifft praktisch nie, mehr Threads kosten nur mehr Strom.</div>
<dl><dt>Status</dt><dd><b>{status}</b></dd><dt>Hashrate</dt><dd>{hashrate}</dd>
<dt>Threads</dt><dd>{threads} von {max_threads} (Mehrverbrauch {watt_est})</dd><dt>Shares</dt><dd>{accepted}</dd><dt>Laufzeit</dt><dd>{uptime_h} h</dd>
<dt>Wallet</dt><dd>{address_html}</dd></dl>
<form method="post" action="/{action}"><button class="{cls}" {disabled}>{label}</button></form>
<form method="post" action="/threads" style="margin-top:22px">
<label class="mut" for="t">Threads (je ca. 5 W, der erste ca. 15 W)</label>
<select id="t" name="threads">{options}</select>
<button>Übernehmen</button></form>
<form method="post" action="/address" style="margin-top:22px">
<label class="mut" for="a">Bitcoin-Adresse (Auszahlung bei Treffer)</label>
<input id="a" name="address" value="{address}" placeholder="bc1q..." autocomplete="off">
<button>Adresse speichern</button></form>
<pre>{last}</pre></main></body></html>"""


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

    def do_GET(self):
        s = status()
        if self.path == "/api/status":
            return self.send(200, json.dumps(s, ensure_ascii=False), "application/json")
        if self.path != "/":
            return self.send(404, "nicht gefunden", "text/plain")
        a = html.escape(s["address"])
        self.send(200, PAGE.format(
            threads=threads(), max_threads=MAX_THREADS, watt_est=f"~{10 + 5 * threads()} W",
            options="".join(f'<option value="{i}"{" selected" if i == threads() else ""}>{i}</option>'
                            for i in range(1, MAX_THREADS + 1)),
            status=s["status"], hashrate=s["hashrate"], accepted=s["accepted"],
            uptime_h=s["uptime_h"], address=a, last=html.escape(s["last"]),
            address_html=f'<a href="{html.escape(s["pool_stats"])}">{a}</a>' if a else "noch keine",
            action="stop" if s["running"] else "start", cls="stop" if s["running"] else "",
            label="Stoppen" if s["running"] else "Starten", disabled="" if a or s["running"] else "disabled"))

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        form = parse_qs(self.rfile.read(n).decode())
        if self.path == "/start":
            start()
        elif self.path == "/stop":
            stop()
        elif self.path == "/threads":
            try:
                t = int(form.get("threads", ["1"])[0])
            except ValueError:
                return self.send(400, "Ungültige Anzahl.", "text/plain; charset=utf-8")
            was = bool(proc and proc.poll() is None)
            stop()
            THREADS_FILE.write_text(str(min(max(t, 1), MAX_THREADS)))
            if was:
                start()
        elif self.path == "/address":
            a = form.get("address", [""])[0].strip()
            if a and not ADDR_RE.match(a):
                return self.send(400, "Das sieht nicht nach einer Bitcoin-Adresse aus.", "text/plain; charset=utf-8")
            was = bool(proc and proc.poll() is None)
            stop()
            ADDR_FILE.write_text(a)
            if was and a:
                start()
        self.send_response(303)
        self.send_header("Location", "/")
        self.end_headers()


if RUN_FILE.exists():
    start()
ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
