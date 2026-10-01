import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
GENERATED = ROOT / "generated"
OVERRIDES = ROOT / "data" / "overrides"

CHAR_URL = "https://raw.githubusercontent.com/mozillazg/pinyin-data/master/pinyin.txt"
PHRASE_URL = "https://raw.githubusercontent.com/mozillazg/phrase-pinyin-data/master/pinyin.txt"

def fetch(url):
    req = Request(url, headers={"User-Agent": "chinese-typing-dictionary-builder"})
    with urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")

def parse_mapping(text, phrase_mode):
    result = defaultdict(set)
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "#" in line:
            line = line.split("#", 1)[0].rstrip()
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key or not value:
            continue

        if phrase_mode:
            # Phrase data is one pinyin syllable per character.
            result[key].add(value)
        else:
            # Character pinyin data can contain comma-separated readings.
            for reading in value.split(","):
                reading = reading.strip()
                if reading:
                    result[key].add(reading)
    return result

def load_overrides(path):
    result = defaultdict(set)
    if not path.exists():
        return result
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "\t" not in line:
            continue
        key, value = line.split("\t", 1)
        key, value = key.strip(), value.strip()
        if key and value:
            result[key].add(value)
    return result

def merge(base, override):
    for key, values in override.items():
        base[key] = set(values)

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    GENERATED.mkdir(parents=True, exist_ok=True)

    chars = parse_mapping(fetch(CHAR_URL), False)
    phrases = parse_mapping(fetch(PHRASE_URL), True)

    merge(phrases, load_overrides(OVERRIDES / "phrases.txt"))
    merge(chars, load_overrides(OVERRIDES / "characters.txt"))

    # Ignore entries that are not useful to the typing engine.
    phrases = {
        k: v for k, v in phrases.items()
        if len(k) >= 2 and all("\u3400" <= ch <= "\u9fff" or "\u3400" <= ch <= "\u4dbf" for ch in k)
    }
    chars = {
        k: v for k, v in chars.items()
        if len(k) == 1 and ("\u3400" <= k <= "\u9fff" or "\u3400" <= k <= "\u4dbf")
    }

    dictionary = GENERATED / "dictionary.tsv"
    with dictionary.open("w", encoding="utf-8", newline="\n") as f:
        for key in sorted(phrases, key=lambda x: (-len(x), x)):
            readings = sorted(phrases[key])
            f.write("P\t" + key + "\t" + " || ".join(readings) + "\n")
        for key in sorted(chars):
            readings = sorted(chars[key])
            f.write("C\t" + key + "\t" + " || ".join(readings) + "\n")

    manifest = {
        "format": 1,
        "dictionary": "dictionary.tsv",
        "encoding": "UTF-8",
        "phrase_count": len(phrases),
        "character_count": len(chars),
        "sources": {
            "character": CHAR_URL,
            "phrase": PHRASE_URL
        },
        "sha256": sha256(dictionary)
    }

    (GENERATED / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8"
    )

    print(json.dumps(manifest, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
