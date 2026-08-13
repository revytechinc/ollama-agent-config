#!/bin/sh
# cloudbsd-ollama-agents — configure Claude Code, Junie, and Grok for Ollama.
set -eu
# pipefail is supported on this host's /bin/sh
( set -o pipefail ) 2>/dev/null && set -o pipefail

if [ -z "${CBA_DIST:-}" ]; then
  case "$0" in
    /*) CBA_ROOT=$(dirname "$0") ;;
    *) CBA_ROOT=$(CDPATH= cd "$(dirname "$0")" && pwd) ;;
  esac
  . "$CBA_ROOT/lib/00-posix.sh"
  . "$CBA_ROOT/lib/10-linuxulator.sh"
  . "$CBA_ROOT/lib/20-discover.sh"
  . "$CBA_ROOT/lib/30-classify.sh"
  . "$CBA_ROOT/lib/40-backup.sh"
  . "$CBA_ROOT/lib/50-validate.sh"
  . "$CBA_ROOT/adapters/claude.sh"
  . "$CBA_ROOT/adapters/junie.sh"
  . "$CBA_ROOT/adapters/grok.sh"
fi

cba_detect_tools() {
  _list=""
  if cba_tool_claude; then _list="${_list},claude"; fi
  if cba_tool_junie; then _list="${_list},junie"; fi
  if cba_tool_grok; then _list="${_list},grok"; fi
  printf '%s\n' "${_list#,}"
}

cba_has_tool() {
  _want=$1
  _ifs=$IFS
  IFS=,
  for t in $CBA_TOOLS; do
    if [ "$t" = "$_want" ]; then
      IFS=$_ifs
      return 0
    fi
  done
  IFS=$_ifs
  return 1
}

cba_run_one() {
  _name=$1
  case "$_name" in
    claude) cba_claude_run ;;
    junie) cba_junie_run ;;
    grok) cba_grok_run ;;
    *) cba_log "skip unknown tool $_name"; return 0 ;;
  esac
}

cba_prune_one() {
  _name=$1
  case "$_name" in
    claude) cba_claude_prune ;;
    junie) cba_junie_prune ;;
    grok) cba_grok_prune ;;
  esac
}

cba_main() {
  # env fallbacks if flags empty
  [ -n "$CBA_DEFAULT_MODEL" ] || CBA_DEFAULT_MODEL=${CLOUDBSD_DEFAULT_MODEL:-}
  [ -n "$CBA_HAIKU_MODEL" ] || CBA_HAIKU_MODEL=${CLOUDBSD_HAIKU_MODEL:-}
  [ -n "$CBA_SONNET_MODEL" ] || CBA_SONNET_MODEL=${CLOUDBSD_SONNET_MODEL:-}
  [ -n "$CBA_OPUS_MODEL" ] || CBA_OPUS_MODEL=${CLOUDBSD_OPUS_MODEL:-}
  [ -n "$CBA_FABLE_MODEL" ] || CBA_FABLE_MODEL=${CLOUDBSD_FABLE_MODEL:-}

  cba_need_bin python3 "pkg install python3"
  cba_need_bin curl "pkg install curl"
  cba_mkwork
  trap cba_cleanup EXIT INT TERM

  cba_discover
  cba_classify

  if [ -z "$CBA_TOOLS" ]; then
    CBA_TOOLS=$(cba_detect_tools)
  fi
  if [ -z "$CBA_TOOLS" ]; then
    cba_die "no tools detected (claude/junie/grok). Pass --tools="
  fi

  if [ "$(uname -s)" = "FreeBSD" ]; then
    if cba_has_tool claude || cba_has_tool junie; then
      if ! cba_linuxulator_ok; then
        if [ "$CBA_STRICT" -eq 1 ]; then
          cba_die "Linuxulator check failed"
        fi
      fi
    fi
  fi

  cba_log "host: $CBA_HOST"
  cba_log "catalog: $CBA_N_TOTAL total, $CBA_N_COMP completion, $CBA_N_SKIP skip"
  cba_log "roles: haiku=$CBA_ROLE_HAIKU sonnet=$CBA_ROLE_SONNET opus=$CBA_ROLE_OPUS fable=$CBA_ROLE_FABLE"
  cba_log "junie primary=$CBA_JUNIE_PRI local=$CBA_JUNIE_LOC"
  cba_log "tools: $CBA_TOOLS"

  if [ "$CBA_DRY_RUN" -eq 1 ]; then
    cba_log "dry-run: no files written"
    exit 0
  fi

  _ok=1
  _ifs=$IFS
  IFS=,
  for t in $CBA_TOOLS; do
    IFS=$_ifs
    cba_log "adapter: $t"
    if ! cba_run_one "$t"; then
      cba_log "adapter $t failed"
      _ok=0
      break
    fi
    IFS=,
  done
  IFS=$_ifs

  if [ "$_ok" -eq 1 ] && [ "$CBA_PRUNE" -eq 1 ] && [ "$CBA_VALIDATE_ONLY" -eq 0 ]; then
    IFS=,
    for t in $CBA_TOOLS; do
      IFS=$_ifs
      cba_log "prune: $t"
      cba_prune_one "$t" || _ok=0
      IFS=,
    done
    IFS=$_ifs
  fi

  if [ "$CBA_JSON" -eq 1 ]; then
    python3 -c '
import json,sys
print(json.dumps({
  "ok": sys.argv[1]=="1",
  "host": sys.argv[2],
  "catalog": {"total": int(sys.argv[3]), "completion": int(sys.argv[4]), "skip": int(sys.argv[5])},
  "roles": {"haiku": sys.argv[6], "sonnet": sys.argv[7], "opus": sys.argv[8], "fable": sys.argv[9]},
  "tools": sys.argv[10],
}, indent=2))
' "$_ok" "$CBA_HOST" "$CBA_N_TOTAL" "$CBA_N_COMP" "$CBA_N_SKIP" \
      "$CBA_ROLE_HAIKU" "$CBA_ROLE_SONNET" "$CBA_ROLE_OPUS" "$CBA_ROLE_FABLE" "$CBA_TOOLS"
  fi

  [ "$_ok" -eq 1 ]
}

cba_parse_args "$@"
cba_main
