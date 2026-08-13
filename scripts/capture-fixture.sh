#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
HOST=${OLLAMA_HOST:-http://127.0.0.1:11434}
curl -fsS "$HOST/api/tags" | python3 -c '
import json,sys
data=json.load(sys.stdin)
out={"models":[]}
for m in data.get("models",[]):
    d=m.get("details") or {}
    out["models"].append({
        "name": m.get("name"),
        "model": m.get("model") or m.get("name"),
        "size": m.get("size",0),
        "modified_at": m.get("modified_at"),
        "capabilities": m.get("capabilities") or [],
        "details": {
            "family": d.get("family"),
            "parameter_size": d.get("parameter_size"),
            "quantization_level": d.get("quantization_level"),
        },
    })
print(json.dumps(out, indent=2))
' > "$ROOT/testdata/api-tags.fixture.json"
echo "updated testdata/api-tags.fixture.json"
