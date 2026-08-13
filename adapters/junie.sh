cba_tool_junie() {
  command -v junie >/dev/null 2>&1 && return 0
  [ -x "$HOME/bin/junie" ] && return 0
  [ -x "$HOME/.local/bin/junie" ]
}

cba_junie_faster() {
  python3 -c '
import json,sys
sys.path.insert(0, sys.argv[1])
from catalog import faster_for_profile, load_models, completion_models
tags=json.load(open(sys.argv[2]))
haiku=sys.argv[3]
pid=sys.argv[4]
comp=completion_models(load_models(tags))
print(faster_for_profile(pid, haiku, comp))
' "${CBA_ROOT:-$CBA_WORKDIR}/lib" "$CBA_TAGS" "$CBA_ROLE_HAIKU" "$1"
}

cba_junie_write() {
  _root=${CBA_JUNIE_HOME:-$HOME/.junie}
  mkdir -p "$_root/models"
  _base="$CBA_HOST/v1/chat/completions"
  cba_py json_util.py merge-junie-config --file "$_root/config.json" --model custom:ollama
  cba_py json_util.py write-junie-all \
    --models-dir "$_root/models" \
    --tags "$CBA_TAGS" \
    --models-json "$CBA_CLASS" \
    --haiku "$CBA_ROLE_HAIKU" \
    --primary "$CBA_JUNIE_PRI" \
    --local "$CBA_JUNIE_LOC" \
    --base-url "$_base"
}

cba_junie_validate() {
  _root=${CBA_JUNIE_HOME:-$HOME/.junie}
  cba_py json_util.py check --file "$_root/config.json" --schema junie-config || return 1
  cba_py json_util.py check --file "$_root/models/ollama.json" --schema junie-profile || return 1
  if ! cba_endpoint_ok "$CBA_HOST"; then
    cba_log "warn: endpoint check failed"
    [ "$CBA_STRICT" -eq 1 ] && return 1
  fi
  return 0
}

cba_junie_backup() {
  _root=${CBA_JUNIE_HOME:-$HOME/.junie}
  cba_backup_file "$_root/config.json" "$_root/backups" 644 >/dev/null
  cba_backup_tar "$_root/models" "$_root/backups"
}

cba_junie_run() {
  if [ "$CBA_VALIDATE_ONLY" -eq 1 ]; then
    cba_junie_validate
    return $?
  fi
  CBA_JUNIE_BACKUP=$(cba_junie_backup)
  cba_junie_write || return 1
  cba_junie_validate
}

cba_junie_prune() {
  _root=${CBA_JUNIE_HOME:-$HOME/.junie}
  python3 -c '
import json,os,sys
cls=json.load(open(sys.argv[1]))
d=sys.argv[2]
keep=set()
from pathlib import Path
sys.path.insert(0, sys.argv[3])
from catalog import junie_slug
for n in cls["completion"]:
    keep.add(junie_slug(n)+".json")
keep.add("ollama.json")
keep.add("ollama-local.json")
for fn in os.listdir(d):
    if not fn.endswith(".json"):
        continue
    if fn in keep:
        continue
    # only delete if it looks like a managed ollama profile
    try:
        data=json.load(open(os.path.join(d,fn)))
    except Exception:
        continue
    if data.get("apiType")!="OpenAICompletion":
        continue
    if not str(data.get("baseUrl","")).endswith("/v1/chat/completions"):
        continue
    os.unlink(os.path.join(d,fn))
    print("pruned", fn, file=sys.stderr)
' "$CBA_CLASS" "$_root/models" "${CBA_ROOT:-$CBA_WORKDIR}/lib"
}
