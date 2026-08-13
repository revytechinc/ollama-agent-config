cba_http_get() {
  _url=$1
  _out=$2
  if [ -n "${OLLAMA_API_KEY:-}" ]; then
    cba_py fetch.py get "$_url" --out "$_out" --bearer "$OLLAMA_API_KEY"
  else
    cba_py fetch.py get "$_url" --out "$_out"
  fi
}

cba_discover() {
  CBA_HOST=$(cba_strip_slash "$(cba_host_default)")
  CBA_TAGS="$CBA_WORKDIR/tags.json"
  if [ -n "$CBA_CATALOG_FILE" ]; then
    cp "$CBA_CATALOG_FILE" "$CBA_TAGS" || cba_die "cannot read --catalog-file"
    return 0
  fi
  if cba_http_get "$CBA_HOST/api/tags" "$CBA_TAGS"; then
    return 0
  fi
  if cba_http_get "$CBA_HOST/v1/models" "$CBA_WORKDIR/v1models.json"; then
    python3 -c '
import json,sys
p=sys.argv[1]; o=sys.argv[2]
d=json.load(open(p))
models=[{"name": m.get("id"), "capabilities": []} for m in d.get("data",[]) if m.get("id")]
json.dump({"models": models}, open(o,"w"), indent=2)
' "$CBA_WORKDIR/v1models.json" "$CBA_TAGS"
    return 0
  fi
  if command -v ollama >/dev/null 2>&1; then
    ollama list > "$CBA_WORKDIR/ollama.list" || true
    python3 -c '
import json,sys
names=[]
for line in open(sys.argv[1]):
    if line.startswith("NAME") or not line.strip():
        continue
    names.append(line.split()[0])
json.dump({"models":[{"name":n,"capabilities":[]} for n in names]}, open(sys.argv[2],"w"), indent=2)
' "$CBA_WORKDIR/ollama.list" "$CBA_TAGS"
    return 0
  fi
  cba_die "cannot discover models from $CBA_HOST"
}
