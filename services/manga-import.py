# Uebernimmt von Suwayomi geladene Kapitel in die Manga-Bibliothek (Komga).
# Suwayomi legt sie unter <downloads>/mangas/<Quelle>/<Titel>/<Gruppe>_<Kapitel>.cbz ab; hier
# bekommen sie einen Hardlink im Serienordner der Bibliothek als "<Serie> Ch.NNN.cbz"
# (gleiches Schema wie die vorhandenen Kapitel, kein zusaetzlicher Speicher, Suwayomi behaelt
# seine Datei). Kapitel, die es in der Bibliothek schon gibt, werden uebersprungen.
# Serienordner: zuordnung.json im Download-Ordner ({"Titel in Suwayomi": "Ordner"}), sonst
# gleicher Name (ohne Gross-/Kleinschreibung und Sonderzeichen), sonst neuer Ordner.
# Aufgeteilte Kapitel (35.1, 35.2) nur, wenn es Kapitel 35 noch nicht ganz gibt; Bonuskapitel
# (einzelnes 35.1 oder 35.5) immer.
# Manganato liefert jede Seite als zwei Bilder: Seite (meist 1500 px hoch) und die unteren
# ~100 px als eigenes Bild, Reader zeigen das als abgeschnittene Seite plus Fetzen. Solche
# Streifen werden vor dem Uebernehmen wieder unten an die Seite davor geklebt (Original nach
# <downloads>/_original-manganato-streifen).
# Aufruf: manga-import <downloads> <bibliothek>
import io, json, os, re, sys, zipfile
from pathlib import Path

from PIL import Image

src, lib = Path(sys.argv[1]) / "mangas", Path(sys.argv[2])
backup = Path(sys.argv[1]) / "_original-manganato-streifen"
CH = re.compile(r" Ch\.(\d+(?:\.\d+)?)")
IMG = (".jpg", ".jpeg", ".png", ".webp")


def stitch_strips(cbz):
    """Schmale Streifen (<= 130 px, gleiche Breite) an die Seite davor kleben. True, wenn geaendert."""
    try:
        z = zipfile.ZipFile(cbz)
        names = z.namelist()
        pages, merged = [], 0  # (name, Image oder None, Rohdaten)
        for n in sorted(n for n in names if n.lower().endswith(IMG)):
            raw = z.read(n)
            im = Image.open(io.BytesIO(raw))
            w, h = im.size
            if pages and h <= 130 and w > 500:
                pn, pim, praw = pages[-1]
                pim = pim or Image.open(io.BytesIO(praw))
                if pim.size[0] == w:
                    new = Image.new("RGB", (w, pim.size[1] + h), "white")
                    new.paste(pim.convert("RGB"), (0, 0))
                    new.paste(im.convert("RGB"), (0, pim.size[1]))
                    pages[-1] = (pn, new, None)
                    merged += 1
                    continue
            pages.append((n, None, raw))
    except Exception as e:
        print(f"{cbz}: nicht lesbar ({e})", flush=True)
        return False
    if not merged:
        return False
    tmp = cbz.with_name(cbz.name + ".neu")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_STORED) as out:
        for n in names:
            if n.lower().endswith(IMG):
                continue
            data = z.read(n)
            if n.lower() == "comicinfo.xml":
                data = re.sub(rb"<PageCount>\d+</PageCount>", b"<PageCount>%d</PageCount>" % len(pages), data)
            out.writestr(n, data)
        for n, im, raw in pages:
            if im is None:
                out.writestr(n, raw)
            else:
                b = io.BytesIO()
                im.save(b, "WEBP", quality=92, method=4)
                out.writestr(os.path.splitext(n)[0] + ".webp", b.getvalue())
    dest = backup / cbz.parent.parent.name / cbz.parent.name
    dest.mkdir(parents=True, exist_ok=True)
    os.rename(cbz, dest / cbz.name)
    os.rename(tmp, cbz)
    print(f"{cbz.parent.name}/{cbz.name}: {merged} Streifen angeklebt", flush=True)
    return True


def norm(s):
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def number(cbz):
    try:
        with zipfile.ZipFile(cbz) as z:
            if "ComicInfo.xml" in z.namelist():
                m = re.search(r"<Number>([\d.]+)</Number>", z.read("ComicInfo.xml").decode("utf-8", "replace"))
                if m:
                    return m.group(1)
    except zipfile.BadZipFile:
        return None
    m = re.search(r"(?:Chapter|Ch\.?)\s*(\d+(?:\.\d+)?)", cbz.stem, re.I)
    return m.group(1) if m else None


def num_key(n):
    return float(n)


mapping_file = src.parent / "zuordnung.json"
mapping = json.loads(mapping_file.read_text()) if mapping_file.exists() else {}
folders = {norm(p.name): p for p in lib.iterdir() if p.is_dir()}
added = 0
for title_dir in sorted(p for p in src.glob("*/*") if p.is_dir()):
    title = title_dir.name
    target = lib / mapping[title] if title in mapping else folders.get(norm(title), lib / title)
    have = {}
    if target.is_dir():
        for f in target.glob("*.cbz"):
            m = CH.search(f.name)
            if m:
                have[num_key(m.group(1))] = f
    files = [(cbz, n) for cbz in sorted(title_dir.glob("*.cbz")) if (n := number(cbz)) is not None]
    # Manganato teilt manche Kapitel in Teile 35.1, 35.2 (lueckenlos ab .1); einzelne .1/.5
    # sind dagegen Bonuskapitel. Teile nicht neben ein vorhandenes ganzes Kapitel legen und
    # ein ganzes Kapitel nicht neben vorhandene Teile.
    parts = {}
    for _, n in files:
        a, _, b = n.partition(".")
        if b.strip("0"):
            parts.setdefault(int(a), set()).add(int(b))
    split = {a for a, bs in parts.items() if len(bs) >= 2 and bs == set(range(1, len(bs) + 1))}
    for cbz, n in files:
        if num_key(n) in have:
            continue
        whole = int(num_key(n))
        if (whole != num_key(n) and whole in split and float(whole) in have) or \
                (whole == num_key(n) and float(f"{whole}.1") in have and float(f"{whole}.2") in have):
            continue
        nums = list(have) + [num_key(n)]
        width = max(3, len(str(int(max(nums)))))
        a, _, b = n.partition(".")
        b = b.rstrip("0")
        dest = target / f"{target.name} Ch.{a.zfill(width)}{'.' + b if b else ''}.cbz"
        target.mkdir(exist_ok=True)
        if "Manganato" in title_dir.parent.name:
            stitch_strips(cbz)
        try:
            os.link(cbz, dest)
        except FileExistsError:
            continue
        have[num_key(n)] = dest
        added += 1
        print(f"{dest.relative_to(lib)}", flush=True)
print(f"{added} neue Kapitel uebernommen")
