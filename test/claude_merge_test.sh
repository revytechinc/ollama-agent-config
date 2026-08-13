#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
python3 "$ROOT/lib/catalog.py" classify --tags "$ROOT/testdata/mini-tags.json" --out "$TMP/class.json"
cp "$ROOT/testdata/claude-settings.in.json" "$TMP/settings.json"
python3 - <<PY
import json
env={
  "ANTHROPIC_AUTH_TOKEN":"ollama",
  "ANTHROPIC_API_KEY":"",
  "ANTHROPIC_BASE_URL":"http://127.0.0.1:11434",
  "ANTHROPIC_MODEL":"qwen2.5-coder:14b",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL":"granite4.1:8b",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME":"granite4.1:8b",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION":"Fast local Ollama (Haiku)",
  "ANTHROPIC_DEFAULT_SONNET_MODEL":"qwen2.5-coder:14b",
  "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME":"qwen2.5-coder:14b",
  "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION":"Local Ollama coder (Sonnet)",
  "ANTHROPIC_DEFAULT_OPUS_MODEL":"qwen3-coder-next:latest",
  "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME":"qwen3-coder-next",
  "ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION":"Large local Ollama coder (Opus)",
  "ANTHROPIC_DEFAULT_FABLE_MODEL":"muse-glimmer:30b",
  "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME":"muse-glimmer:30b",
  "ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION":"Newest local Ollama (Fable)",
  "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY":"1",
  "API_TIMEOUT_MS":"1200000",
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1",
  "DISABLE_TELEMETRY":"1",
  "DISABLE_ERROR_REPORTING":"1",
  "DISABLE_PROMPT_CACHING":"1",
}
open("$TMP/env.json","w").write(json.dumps(env))
PY
python3 "$ROOT/lib/json_util.py" merge-claude \
  --file "$TMP/settings.json" --env-json "$TMP/env.json" --models-json "$TMP/class.json"
python3 "$ROOT/lib/json_util.py" check --file "$TMP/settings.json" --schema claude
python3 - <<PY
import json
d=json.load(open("$TMP/settings.json"))
am=d["availableModels"]
assert am[:4]==["sonnet","haiku","opus","fable"], am[:8]
assert am.count("sonnet")==1
assert "my-proxy-coder" in am
assert "nomic-embed-text:latest" not in am
assert "qwen3-coder-next:latest" in am
assert d["theme"]=="dark-ansi"
assert d["env"]["ANTHROPIC_BASE_URL"]=="http://127.0.0.1:11434"
print("claude merge ok", am)
PY
rm -rf "$TMP"
