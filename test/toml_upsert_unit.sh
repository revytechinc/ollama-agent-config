#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
from toml_upsert import MANAGED_RE
ok = "[model.ollama-direct-granite4-1-8b]"
assert MANAGED_RE.match(ok), ok
negs = [
    '[model.ollama-direct-foo.extra_headers]',
    '[model."grok-4.5"]',
    '[model."ollama-direct-x"]',
    '[model.ollama-nginx-qwen3-5-cloud]',
    '[model.minimax-direct-m3]',
    '[model.litellm-minimax]',
    '[models]',
]
for n in negs:
    assert not MANAGED_RE.match(n), n
print("regex negatives ok")
PY
