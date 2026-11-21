# episode-verify: prueft eine schon benannte Staffel oder ganze Serie, ob die Folgennummern im
# Dateinamen zum Inhalt passen. Aendert nichts. Aufruf im Container (siehe episode-matcher.nix):
#   docker exec episode-matcher episode-verify "/mnt/tank/media/TV/Friends/Season 03" [--tmdb-id 1668]
#   docker exec episode-matcher episode-verify "/mnt/tank/media/TV/Friends"   (alle Staffeln)
#   docker exec episode-matcher episode-verify "/mnt/tank/media/TV/Friends" --seasons 1,4-6
# mkv-episode-matcher ueberspringt Dateien mit S01E02 im Namen, deshalb werden neutral benannte
# Symlinks in /data/verify/<Serie>/Season NN/ angelegt und nur im Probemodus (--dry-run) abgeglichen.
import argparse
import collections
import json
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("season_dir", type=Path, help="Staffel- oder Serienordner, z. B. .../Friends/Season 03 oder .../Friends")
ap.add_argument("--tmdb-id", type=int, help="TMDb-ID der Serie (bei mehrdeutigen Namen)")
ap.add_argument("--season", type=int, help="Staffel, falls nicht aus dem Ordnernamen lesbar")
ap.add_argument("--no-specials", action="store_true", help="Season 0/Specials beim Serienordner auslassen")
ap.add_argument("--seasons", help="beim Serienordner nur diese Staffeln, z. B. 3 oder 1,4-6")
ap.add_argument("--show", help="Serienname, falls nicht aus dem Elternordner lesbar")
a = ap.parse_args()

PROGRESS = sys.stderr  # Fortschritt auf stderr: "> datei.txt" bekommt nur die Ergebnisliste
# mkv-match loggt pro Datei genau eine dieser Zeilen, wenn sie fertig ist
FILE_DONE = re.compile(r"Found definitive match|Processed \d+ successful segments")
SEGMENT = re.compile(r"Checking segment (\d+)/(\d+)")


def run_with_progress(cmd, total, season):
    """mkv-match starten, Fortschritt aus dessen Log anzeigen; gibt (stdout, Ende von stderr) zurueck."""
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    chunks = []
    t = threading.Thread(target=lambda: chunks.append(p.stdout.read()))
    t.start()
    tail = collections.deque(maxlen=40)
    done, seg, start = 0, "", time.time()
    tty = PROGRESS.isatty()

    def show(final=False):
        pct = done * 100 // total
        mins = (time.time() - start) / 60
        eta = f", noch ca. {mins / done * (total - done):.0f} min" if done and done < total else ""
        line = f"  Staffel {season}: {done}/{total} Folgen ({pct} %){seg}, {mins:.1f} min{eta}"
        if tty:
            PROGRESS.write("\r\033[K" + line + ("\n" if final else ""))
        elif final or not seg:
            PROGRESS.write(line + "\n")
        PROGRESS.flush()

    show()
    for line in p.stderr:
        tail.append(line)
        m = SEGMENT.search(line)
        if m:
            seg = f" – Ausschnitt {m.group(1)}/{m.group(2)}"
            if tty:
                show()
        elif FILE_DONE.search(line):
            done, seg = min(done + 1, total), ""
            show()
    p.wait()
    t.join()
    done = total
    seg = ""
    show(final=True)
    return "".join(chunks), "".join(tail)


def check(d, season, show):
    """Eine Staffel pruefen, gibt (ok, falsch, unklar) zurueck."""

    files = sorted(p for p in d.iterdir() if p.suffix.lower() == ".mkv")
    if not files:
        print(f"Staffel {season}: keine .mkv-Dateien")
        return 0, 0, 0

    work = Path("/data/verify") / str(int(time.time())) / show / f"Season {season:02d}"
    work.mkdir(parents=True)
    links = {}
    for i, f in enumerate(files):
        link = work / f"f{i:03d}.mkv"
        link.symlink_to(f)
        links[str(link)] = f

    cmd = ["mkv-match", "match", str(work), "--dry-run", "--json", "--season", str(season)]
    if a.tmdb_id:
        cmd += ["--tmdb-id", str(a.tmdb_id)]
    print(f"Pruefe {len(files)} Dateien: {show}, Staffel {season} ...", flush=True)
    out, err_tail = run_with_progress(cmd, len(files), season)
    shutil.rmtree(work.parent.parent, ignore_errors=True)

    start = out.find("\n{")
    try:
        data = json.loads(out[start + 1:] if start >= 0 else out)
    except json.JSONDecodeError:
        sys.stderr.write(err_tail)
        print(f"Staffel {season}: keine Ergebnisse von mkv-match (Fehler oben)")
        return 0, 0, len(files)

    found = {}
    for res in data.get("results", []):
        found[res["original_file"]] = (res["season"], res["episode"], res["confidence"])

    def claimed(name):
        m = re.search(r"[Ss](\d{1,2})[Ee](\d{1,3})", name) or re.search(r"(\d{1,2})x(\d{1,3})", name)
        return (int(m.group(1)), int(m.group(2))) if m else None

    ok = wrong = unknown = 0
    print()
    for link, f in links.items():
        c = claimed(f.name)
        c_s = f"S{c[0]:02d}E{c[1]:02d}" if c else "  ?   "
        if link in found:
            s, e, conf = found[link]
            g = f"S{s:02d}E{e:02d}"
            if c and (s, e) == c:
                status, ok = "ok    ", ok + 1
            else:
                status, wrong = "FALSCH", wrong + 1
            print(f"{status}  Name {c_s}  Inhalt {g} ({conf:.2f})  {f.name}")
        else:
            unknown += 1
            print(f"unklar  Name {c_s}  Inhalt   ?           {f.name}")
    print(f"\nStaffel {season}: {ok} passen, {wrong} falsch, {unknown} nicht erkannt\n")
    return ok, wrong, unknown


def season_of(p):
    if re.search(r"special", p.name, re.I):
        return 0
    m = re.match(r"(?:season|staffel|s)\s*0*(\d+)", p.name, re.I)
    return int(m.group(1)) if m else None


d = a.season_dir.resolve()
if not d.is_dir():
    sys.exit(f"Ordner nicht gefunden: {d}")
subs = sorted((season_of(p), p) for p in d.iterdir() if p.is_dir() and season_of(p) is not None)
if subs and a.season is None:
    # Serienordner: alle Staffeln nacheinander
    show = a.show or d.name
    total = [0, 0, 0]
    wanted = None
    if a.seasons:
        wanted = set()
        for part in a.seasons.split(","):
            lo, _, hi = part.strip().partition("-")
            wanted.update(range(int(lo), int(hi or lo) + 1))
    for season, sd in subs:
        if season == 0 and a.no_specials:
            continue
        if wanted is not None and season not in wanted:
            continue
        for i, n in enumerate(check(sd, season, show)):
            total[i] += n
    print(f"Gesamt {show}: {total[0]} passen, {total[1]} falsch, {total[2]} nicht erkannt "
          "(Untertitel fehlt/abweichend, Doppelfolge, Extra)")
else:
    season = a.season
    if season is None:
        season = season_of(d)
        if season is None:
            m = re.search(r"(\d+)", d.name)
            if not m:
                sys.exit("Staffel nicht im Ordnernamen erkennbar, bitte --season angeben")
            season = int(m.group(1))
    check(d, season, a.show or d.parent.name)
