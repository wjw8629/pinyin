import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DICT = ROOT / "generated" / "dictionary.tsv"
MANIFEST = ROOT / "generated" / "manifest.json"

HAN = re.compile(r"^[\u3400-\u4dbf\u4e00-\u9fff]+$")
PY = re.compile(r"^[a-züv]+[1-5]$")

def fail(msg):
    print("ERROR:", msg)
    sys.exit(1)

if not DICT.exists():
    fail("generated/dictionary.tsv does not exist")

if not MANIFEST.exists():
    fail("generated/manifest.json does not exist")

manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

phrase_count = 0
character_count = 0
seen = set()
bad = []

with DICT.open("r", encoding="utf-8") as f:
    for line_no, raw in enumerate(f, 1):
        line = raw.rstrip("\n")
        if not line:
            continue

        parts = line.split("\t")
        if len(parts) != 3:
            bad.append(f"line {line_no}: expected 3 tab-separated fields")
            continue

        kind, text, readings = parts

        if kind not in ("P", "C"):
            bad.append(f"line {line_no}: invalid type {kind!r}")

        if kind == "P" and len(text) < 2:
            bad.append(f"line {line_no}: phrase is shorter than 2 characters")

        if kind == "C" and len(text) != 1:
            bad.append(f"line {line_no}: character entry is not one character")

        if not HAN.fullmatch(text):
            bad.append(f"line {line_no}: non-Chinese text {text!r}")

        if text in seen:
            bad.append(f"line {line_no}: duplicate key {text!r}")
        seen.add(text)

        for variant in readings.split(" || "):
            syllables = variant.split()
            if len(syllables) != len(text):
                bad.append(
                    f"line {line_no}: {text!r} has {len(text)} chars "
                    f"but {len(syllables)} pinyin syllables"
                )
                continue
            for syllable in syllables:
                if not PY.fullmatch(syllable):
                    bad.append(
                        f"line {line_no}: suspicious pinyin syllable {syllable!r}"
                    )

        if kind == "P":
            phrase_count += 1
        else:
            character_count += 1

if bad:
    print("\n".join(bad[:100]))
    if len(bad) > 100:
        print(f"... and {len(bad) - 100} more errors")
    sys.exit(1)

if manifest.get("phrase_count") != phrase_count:
    fail(f"manifest phrase_count={manifest.get('phrase_count')} but file has {phrase_count}")

if manifest.get("character_count") != character_count:
    fail(
        f"manifest character_count={manifest.get('character_count')} "
        f"but file has {character_count}"
    )

print(f"OK: {phrase_count:,} phrases, {character_count:,} characters")
