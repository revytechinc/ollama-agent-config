#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
cp "$ROOT/testdata/grok-config.redacted.toml" "$TMP/config.toml"
chmod 600 "$TMP/config.toml"
python3 "$ROOT/lib/catalog.py" classify --tags "$ROOT/testdata/mini-tags.json" --out "$TMP/class.json"
# umask 022 must still produce 0600
( umask 022; python3 "$ROOT/lib/toml_upsert.py" upsert \
    --file "$TMP/config.toml" --catalog "$TMP/class.json" --host http://127.0.0.1:11434 )
mode=$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$TMP/config.toml")
[ "$mode" = "0o600" ] || { echo "mode $mode"; exit 1; }
python3 "$ROOT/lib/toml_upsert.py" check --file "$TMP/config.toml" --catalog "$TMP/class.json" --host http://127.0.0.1:11434
python3 - "$TMP/config.toml" <<'PY'
import sys, tomllib, re
text=open(sys.argv[1]).read()
d=tomllib.loads(text)
# nomic still present without --prune
assert "ollama-direct-nomic-embed-text-latest" in d["model"]
# muse-glimmer added
assert "ollama-direct-muse-glimmer-30b" in d["model"]
# foreign tables intact
assert d["model"]["minimax-direct-m3"]["api_key"]=="REDACTED"
assert d["mcp_servers"]["dummy"]["headers"]["Authorization"]=="Bearer REDACTED"
assert d["models"]["default"]=="grok-4-fast-non-reasoning"
assert d["models"]["default_reasoning_effort"]=="xhigh"
# muse-glimmer appears before [models]
mi=text.index("[model.ollama-direct-muse-glimmer-30b]")
md=text.index("[models]")
assert mi < md
print("upsert without prune ok")
PY
python3 "$ROOT/lib/toml_upsert.py" upsert \
  --file "$TMP/config.toml" --catalog "$TMP/class.json" --host http://127.0.0.1:11434 --prune
python3 - "$TMP/config.toml" <<'PY'
import sys, tomllib
d=tomllib.load(open(sys.argv[1],"rb"))
assert "ollama-direct-nomic-embed-text-latest" not in d["model"]
assert d["model"]["minimax-direct-m3"]["api_key"]=="REDACTED"
print("prune ok")
PY
cp "$ROOT/testdata/grok-config.redacted.toml" "$TMP/config2.toml"
python3 "$ROOT/lib/toml_upsert.py" upsert \
  --file "$TMP/config2.toml" --catalog "$TMP/class.json" --host http://127.0.0.1:11434 \
  --set-default ollama-direct-qwen2-5-coder-14b
python3 - "$TMP/config2.toml" <<'PY'
import sys, tomllib
d=tomllib.load(open(sys.argv[1],"rb"))
assert d["models"]["default"]=="ollama-direct-qwen2-5-coder-14b"
assert d["models"]["default_reasoning_effort"]=="xhigh"
print("set-default ok")
PY
rm -rf "$TMP"
