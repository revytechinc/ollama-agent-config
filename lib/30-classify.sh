cba_classify() {
  CBA_CLASS="$CBA_WORKDIR/class.json"
  set -- classify --tags "$CBA_TAGS" --out "$CBA_CLASS"
  if [ "$CBA_PREFER_CLOUD" -eq 1 ]; then
    set -- "$@" --prefer-cloud
  fi
  if [ "$CBA_PREFER_LOCAL" -eq 1 ]; then
    set -- "$@" --prefer-local
  fi
  if [ -n "$CBA_HAIKU_MODEL" ]; then set -- "$@" --haiku-model "$CBA_HAIKU_MODEL"; fi
  if [ -n "$CBA_SONNET_MODEL" ]; then set -- "$@" --sonnet-model "$CBA_SONNET_MODEL"; fi
  if [ -n "$CBA_OPUS_MODEL" ]; then set -- "$@" --opus-model "$CBA_OPUS_MODEL"; fi
  if [ -n "$CBA_FABLE_MODEL" ]; then set -- "$@" --fable-model "$CBA_FABLE_MODEL"; fi
  if [ -n "$CBA_DEFAULT_MODEL" ]; then set -- "$@" --default-model "$CBA_DEFAULT_MODEL"; fi
  if [ -n "$CBA_JUNIE_PRIMARY" ]; then set -- "$@" --junie-primary "$CBA_JUNIE_PRIMARY"; fi
  cba_py catalog.py "$@" || cba_die "classify failed"
  CBA_ROLE_HAIKU=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["roles"]["haiku"])' "$CBA_CLASS")
  CBA_ROLE_SONNET=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["roles"]["sonnet"])' "$CBA_CLASS")
  CBA_ROLE_OPUS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["roles"]["opus"])' "$CBA_CLASS")
  CBA_ROLE_FABLE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["roles"]["fable"])' "$CBA_CLASS")
  CBA_JUNIE_PRI=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["junie_primary"])' "$CBA_CLASS")
  CBA_JUNIE_LOC=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["junie_local"])' "$CBA_CLASS")
  CBA_N_COMP=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["completion"]))' "$CBA_CLASS")
  CBA_N_SKIP=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["skip"]))' "$CBA_CLASS")
  CBA_N_TOTAL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["total"])' "$CBA_CLASS")
}
