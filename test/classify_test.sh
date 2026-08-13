#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp)
python3 "$ROOT/lib/catalog.py" classify --tags "$ROOT/testdata/mini-tags.json" --out "$OUT"
python3 - <<PY
import json,sys
d=json.load(open("$OUT"))
assert "nomic-embed-text:latest" in d["skip"], d
assert "qwen2.5-coder:14b" in d["completion"]
assert d["roles"]["haiku"]=="granite4.1:8b", d["roles"]
assert d["roles"]["sonnet"]=="qwen2.5-coder:14b", d["roles"]
assert d["roles"]["opus"]=="qwen3-coder-next:latest", d["roles"]
assert d["roles"]["fable"]=="muse-glimmer:30b", d["roles"]
assert d["junie_primary"]=="kimi-k2.7-code:cloud", d
print("classify defaults ok")
PY
python3 "$ROOT/lib/catalog.py" classify --tags "$ROOT/testdata/mini-tags.json" --out "$OUT" --prefer-cloud
python3 - <<PY
import json
d=json.load(open("$OUT"))
assert d["roles"]["sonnet"]=="kimi-k2.7-code:cloud", d["roles"]
print("prefer-cloud ok")
PY
rm -f "$OUT"
