#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
python3 "$ROOT/lib/catalog.py" classify --tags "$ROOT/testdata/mini-tags.json" --out "$TMP/class.json"
python3 "$ROOT/lib/json_util.py" write-junie-all \
  --models-dir "$TMP/models" \
  --tags "$ROOT/testdata/mini-tags.json" \
  --models-json "$TMP/class.json" \
  --haiku granite4.1:8b \
  --primary kimi-k2.7-code:cloud \
  --local qwen3-coder-next:latest \
  --base-url http://127.0.0.1:11434/v1/chat/completions
python3 "$ROOT/lib/json_util.py" check --file "$TMP/models/ollama.json" --schema junie-profile
python3 - <<PY
import json
p=json.load(open("$TMP/models/granite4.1_8b.json"))
assert p["fasterModel"]["id"]=="granite4.1:3b", p
assert p["apiType"]=="OpenAICompletion"
assert list(p.keys())==["baseUrl","id","apiType","apiKey","temperature","fasterModel"]
o=json.load(open("$TMP/models/ollama.json"))
assert o["id"]=="kimi-k2.7-code:cloud"
print("junie fasterModel pin ok")
PY
# fallback when 3b missing
python3 - <<PY
import json,copy
from pathlib import Path
tags=json.load(open("$ROOT/testdata/mini-tags.json"))
tags["models"]=[m for m in tags["models"] if m["name"]!="granite4.1:3b"]
Path("$TMP/tags2.json").write_text(json.dumps(tags))
PY
python3 "$ROOT/lib/catalog.py" classify --tags "$TMP/tags2.json" --out "$TMP/class2.json"
python3 "$ROOT/lib/json_util.py" write-junie-all \
  --models-dir "$TMP/models2" \
  --tags "$TMP/tags2.json" \
  --models-json "$TMP/class2.json" \
  --haiku granite4.1:8b \
  --primary kimi-k2.7-code:cloud \
  --local qwen3-coder-next:latest \
  --base-url http://127.0.0.1:11434/v1/chat/completions
python3 - <<PY
import json
p=json.load(open("$TMP/models2/granite4.1_8b.json"))
assert p["fasterModel"]["id"]=="qwen2.5-coder:latest", p
print("junie fasterModel fallback ok")
PY
rm -rf "$TMP"
