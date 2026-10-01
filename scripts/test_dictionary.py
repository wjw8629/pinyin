import re
import sys
from pathlib import Path

DICT = Path("generated/dictionary.tsv")

data = {}
with DICT.open("r", encoding="utf-8") as f:
    for raw in f:
        parts = raw.rstrip("\n").split("\t")
        if len(parts) == 3:
            kind, text, readings = parts
            data.setdefault((kind, text), readings)

checks = {
    ("P", "银行"): "yín háng",
    ("P", "行业"): "háng yè",
    ("P", "行走"): "xíng zǒu",
    ("P", "长大"): "zhǎng dà",
    ("P", "长度"): "cháng dù",
}

failed = []
for key, expected in checks.items():
    actual = data.get(key)
    if actual is None:
        failed.append(f"missing {key[1]}")
    elif expected not in actual.split(" || "):
        failed.append(f"{key[1]}: expected {expected!r}, got {actual!r}")

if failed:
    print("\n".join(failed))
    sys.exit(1)

print("OK: contextual pronunciation smoke tests passed")
