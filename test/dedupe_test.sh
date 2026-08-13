#!/bin/sh
# Same digest / same model under two names → one config entry.
# Prefer a name the user already has in a config.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp)
trap 'rm -f "$OUT" "$OUT.pref"' EXIT

python3 "$ROOT/lib/catalog.py" classify --tags "$ROOT/testdata/alias-tags.json" --out "$OUT"
python3 - "$OUT" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
comp=d["completion"]
skip=d["skip"]
assert len(comp)==len(set(comp)), comp
assert "qwen3.6:latest" in comp, comp
assert "qwen3.6:35b" not in comp, comp
assert "qwen3.5:cloud" in comp, comp
assert "qwen3.5:397b-cloud" not in comp, comp
assert "unique-coder:7b" in comp
assert skip.count("nomic-embed-text:latest")+skip.count("nomic-embed-text:v1.5")==1, skip
assert len(skip)==len(set(skip)), skip
# collapsed aliases recorded
aliases=d.get("aliases") or {}
assert aliases.get("qwen3.6:35b")=="qwen3.6:latest", aliases
assert aliases.get("qwen3.5:397b-cloud")=="qwen3.5:cloud", aliases
print("default alias collapse ok")
PY

# User already uses the more specific tags in a session — keep those names.
printf '%s\n' '["qwen3.6:35b","qwen3.5:397b-cloud"]' > "$OUT.pref"
python3 "$ROOT/lib/catalog.py" classify --tags "$ROOT/testdata/alias-tags.json" \
  --prefer-names "$OUT.pref" --out "$OUT"
python3 - "$OUT" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
comp=d["completion"]
assert "qwen3.6:35b" in comp, comp
assert "qwen3.6:latest" not in comp, comp
assert "qwen3.5:397b-cloud" in comp, comp
assert "qwen3.5:cloud" not in comp, comp
assert (d.get("aliases") or {}).get("qwen3.6:latest")=="qwen3.6:35b"
print("prefer existing user names ok")
PY

# Claude allowlist must not list both names for one digest
python3 - "$ROOT" "$OUT" <<'PY'
import json,sys,subprocess
root=sys.argv[1]
cls=sys.argv[2]
settings={
  "theme":"dark-ansi",
  "env":{"ANTHROPIC_AUTH_TOKEN":"ollama","ANTHROPIC_API_KEY":"","ANTHROPIC_BASE_URL":"http://127.0.0.1:11434"},
  "availableModels":["sonnet","haiku","opus","fable","qwen3.6:35b","qwen3.6:latest","qwen3.5:cloud"],
}
open("/tmp/cba-dedupe-settings.json","w").write(json.dumps(settings))
env={
  "ANTHROPIC_AUTH_TOKEN":"ollama","ANTHROPIC_API_KEY":"","ANTHROPIC_BASE_URL":"http://127.0.0.1:11434",
  "ANTHROPIC_MODEL":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION":"x",
  "ANTHROPIC_DEFAULT_SONNET_MODEL":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION":"x",
  "ANTHROPIC_DEFAULT_OPUS_MODEL":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION":"x",
  "ANTHROPIC_DEFAULT_FABLE_MODEL":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME":"unique-coder:7b",
  "ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION":"x",
  "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY":"1",
  "API_TIMEOUT_MS":"1200000",
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1",
  "DISABLE_TELEMETRY":"1",
  "DISABLE_ERROR_REPORTING":"1",
  "DISABLE_PROMPT_CACHING":"1",
}
open("/tmp/cba-dedupe-env.json","w").write(json.dumps(env))
subprocess.check_call([sys.executable, root+"/lib/json_util.py","merge-claude",
  "--file","/tmp/cba-dedupe-settings.json","--env-json","/tmp/cba-dedupe-env.json",
  "--models-json",cls])
am=json.load(open("/tmp/cba-dedupe-settings.json"))["availableModels"]
assert am.count("qwen3.6:35b")+am.count("qwen3.6:latest")==1, am
assert am.count("qwen3.5:cloud")+am.count("qwen3.5:397b-cloud")==1, am
assert "qwen3.6:35b" in am  # keep their name
print("claude allowlist one name per digest ok")
PY

# Junie: one profile per digest; keep their existing filename/id
python3 - "$ROOT" "$OUT" <<'PY'
import json,os,sys,subprocess,tempfile
root=sys.argv[1]
cls=sys.argv[2]
d=tempfile.mkdtemp()
open(os.path.join(d,"qwen3.6_35b.json"),"w").write(json.dumps({
  "baseUrl":"http://127.0.0.1:11434/v1/chat/completions",
  "id":"qwen3.6:35b","apiType":"OpenAICompletion","apiKey":"ollama",
  "temperature":0.6,"fasterModel":{"id":"unique-coder:7b"},
}))
subprocess.check_call([sys.executable, root+"/lib/json_util.py","write-junie-all",
  "--models-dir",d,"--tags",root+"/testdata/alias-tags.json",
  "--models-json",cls,"--haiku","unique-coder:7b",
  "--primary","qwen3.5:397b-cloud","--local","qwen3.6:35b",
  "--base-url","http://127.0.0.1:11434/v1/chat/completions"])
names=sorted(os.listdir(d))
assert "qwen3.6_35b.json" in names
assert "qwen3.6_latest.json" not in names, names
assert "qwen3.5_397b-cloud.json" in names or "qwen3.5_cloud.json" in names
both=int("qwen3.5_397b-cloud.json" in names)+int("qwen3.5_cloud.json" in names)
assert both==1, names
print("junie one profile per digest ok")
PY

echo "dedupe_test ok"
