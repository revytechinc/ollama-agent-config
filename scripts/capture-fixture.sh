#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
HOST=${OLLAMA_HOST:-http://127.0.0.1:11434}
python3 - "$HOST" "$ROOT/testdata/api-tags.fixture.json" <<'PY'
import json, sys, urllib.request
host, out = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(host.rstrip("/") + "/api/tags", timeout=15) as resp:
    data = json.load(resp)
models = []
for m in data.get("models", []):
    d = m.get("details") or {}
    models.append({
        "name": m.get("name"),
        "model": m.get("model") or m.get("name"),
        "digest": m.get("digest") or "",
        "size": m.get("size", 0),
        "modified_at": m.get("modified_at"),
        "capabilities": m.get("capabilities") or [],
        "details": {
            "family": d.get("family"),
            "parameter_size": d.get("parameter_size"),
            "quantization_level": d.get("quantization_level"),
        },
    })
with open(out, "w", encoding="utf-8") as f:
    json.dump({"models": models}, f, indent=2)
    f.write("\n")
print("updated", out)
PY
