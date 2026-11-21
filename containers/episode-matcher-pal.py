# Patch fuer mkv-episode-matcher 1.3.6 (wird nach pip install angewendet, siehe episode-matcher.nix):
# Der Matcher vergleicht den Ton bei Sekunde t nur mit dem Untertitel bei Sekunde t. Europaeische
# DVDs (PAL, 25 fps) laufen 4 % schneller als die meisten Untertitel (23,976 fps); nach 20 min
# liegen beide fast eine Minute auseinander und nichts passt mehr. Deshalb auch die umgerechneten
# Zeiten pruefen und den besten Wert nehmen.
import sys
from pathlib import Path

p = Path(sys.argv[1]) / "mkv_episode_matcher/core/matcher.py"
s = p.read_text()
old = """                ref_text = " ".join(
                    SubtitleReader.extract_subtitle_chunk(
                        sub.content, start_time, start_time + self.chunk_duration
                    )
                )
                ref_text = clean_text(ref_text)

                if not ref_text:
                    continue

                score = self.asr.calculate_match_score(clean_trans, ref_text)
"""
new = """                score = 0.0  # PAL-Patch
                for scale in (1.0, 25 / 23.976, 23.976 / 25):
                    t0 = start_time * scale
                    ref_text = clean_text(" ".join(
                        SubtitleReader.extract_subtitle_chunk(
                            sub.content, t0, t0 + self.chunk_duration * scale
                        )
                    ))
                    if ref_text:
                        score = max(score, self.asr.calculate_match_score(clean_trans, ref_text))
                if score == 0.0:
                    continue
"""
if "# PAL-Patch" in s:
    sys.exit(0)
if old not in s:
    sys.exit("PAL-Patch: Stelle in matcher.py nicht gefunden (andere Version?)")
p.write_text(s.replace(old, new))
print("PAL-Patch angewendet")
