# POSIX helpers. local is function-only.

CBA_DRY_RUN=0
CBA_VALIDATE_ONLY=0
CBA_PRUNE=0
CBA_LIVE_PROBE=0
CBA_JSON=0
CBA_STRICT=0
CBA_VERBOSE=0
CBA_PREFER_CLOUD=0
CBA_PREFER_LOCAL=0
CBA_SET_GROK_DEFAULT=0
CBA_INSTALL_JUNIE=0
CBA_TOOLS=""
CBA_OLLAMA_HOST=""
CBA_CATALOG_FILE=""
CBA_DEFAULT_MODEL=""
CBA_HAIKU_MODEL=""
CBA_SONNET_MODEL=""
CBA_OPUS_MODEL=""
CBA_FABLE_MODEL=""
CBA_JUNIE_PRIMARY=""
CBA_JUNIE_VERSION="2651.4"
CBA_WORKDIR=""

cba_log() {
  printf '%s\n' "$*" >&2
}

cba_verbose() {
  if [ "$CBA_VERBOSE" -eq 1 ]; then
    printf '%s\n' "$*" >&2
  fi
}

cba_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cba_usage() {
  cat <<'EOF'
install-ollama-agent-config.sh [options]

  --help
  --dry-run                 print plan; write nothing
  --validate-only           discover + validate existing configs; write nothing
  --tools=LIST              comma list: claude,junie,grok,codex,opencode
  --ollama-host=URL         default: $OLLAMA_HOST or http://127.0.0.1:11434
  --catalog-file=PATH       use a saved /api/tags JSON
  --default-model=NAME
  --haiku-model=NAME
  --sonnet-model=NAME
  --opus-model=NAME
  --fable-model=NAME
  --junie-primary=SPEC      MODEL | cloud | local
  --prefer-cloud
  --prefer-local
  --prune                   Phase 2 after every selected adapter succeeded
  --live-probe
  --set-grok-default
  --install-junie
  --junie-version=VER       default 2651.4
  --json
  --strict
  --verbose
EOF
}

cba_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) cba_usage; exit 0 ;;
      --dry-run) CBA_DRY_RUN=1; shift ;;
      --validate-only) CBA_VALIDATE_ONLY=1; shift ;;
      --tools=*) CBA_TOOLS=${1#--tools=}; shift ;;
      --tools) CBA_TOOLS=$2; shift 2 ;;
      --ollama-host=*) CBA_OLLAMA_HOST=${1#--ollama-host=}; shift ;;
      --ollama-host) CBA_OLLAMA_HOST=$2; shift 2 ;;
      --catalog-file=*) CBA_CATALOG_FILE=${1#--catalog-file=}; shift ;;
      --catalog-file) CBA_CATALOG_FILE=$2; shift 2 ;;
      --default-model=*) CBA_DEFAULT_MODEL=${1#--default-model=}; shift ;;
      --default-model) CBA_DEFAULT_MODEL=$2; shift 2 ;;
      --haiku-model=*) CBA_HAIKU_MODEL=${1#--haiku-model=}; shift ;;
      --haiku-model) CBA_HAIKU_MODEL=$2; shift 2 ;;
      --sonnet-model=*) CBA_SONNET_MODEL=${1#--sonnet-model=}; shift ;;
      --sonnet-model) CBA_SONNET_MODEL=$2; shift 2 ;;
      --opus-model=*) CBA_OPUS_MODEL=${1#--opus-model=}; shift ;;
      --opus-model) CBA_OPUS_MODEL=$2; shift 2 ;;
      --fable-model=*) CBA_FABLE_MODEL=${1#--fable-model=}; shift ;;
      --fable-model) CBA_FABLE_MODEL=$2; shift 2 ;;
      --junie-primary=*) CBA_JUNIE_PRIMARY=${1#--junie-primary=}; shift ;;
      --junie-primary) CBA_JUNIE_PRIMARY=$2; shift 2 ;;
      --prefer-cloud) CBA_PREFER_CLOUD=1; shift ;;
      --prefer-local) CBA_PREFER_LOCAL=1; shift ;;
      --prune) CBA_PRUNE=1; shift ;;
      --live-probe) CBA_LIVE_PROBE=1; shift ;;
      --set-grok-default) CBA_SET_GROK_DEFAULT=1; shift ;;
      --install-junie) CBA_INSTALL_JUNIE=1; shift ;;
      --junie-version=*) CBA_JUNIE_VERSION=${1#--junie-version=}; shift ;;
      --junie-version) CBA_JUNIE_VERSION=$2; shift 2 ;;
      --json) CBA_JSON=1; shift ;;
      --strict) CBA_STRICT=1; shift ;;
      --verbose) CBA_VERBOSE=1; shift ;;
      --) shift; break ;;
      -*) cba_die "unknown option: $1" ;;
      *) break ;;
    esac
  done
}

cba_need_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    cba_die "missing $1 ($2)"
  fi
}

cba_mkwork() {
  CBA_WORKDIR=${TMPDIR:-/tmp}/cba.$$
  mkdir -p "$CBA_WORKDIR"
  chmod 700 "$CBA_WORKDIR"
}

cba_cleanup() {
  if [ -n "${CBA_WORKDIR:-}" ] && [ -d "$CBA_WORKDIR" ]; then
    rm -rf "$CBA_WORKDIR"
  fi
}

cba_py() {
  _name=$1
  shift
  if [ -n "${CBA_DIST:-}" ]; then
    _script=$(_cba_extract_py "$_name")
    python3 "$_script" "$@"
  else
    python3 "$CBA_ROOT/lib/$_name" "$@"
  fi
}

cba_host_default() {
  if [ -n "$CBA_OLLAMA_HOST" ]; then
    printf '%s\n' "$CBA_OLLAMA_HOST"
    return
  fi
  if [ -n "${CLOUDBSD_OLLAMA_HOST:-}" ]; then
    printf '%s\n' "$CLOUDBSD_OLLAMA_HOST"
    return
  fi
  if [ -n "${OLLAMA_HOST:-}" ]; then
    printf '%s\n' "$OLLAMA_HOST"
    return
  fi
  printf '%s\n' "http://127.0.0.1:11434"
}

cba_strip_slash() {
  _u=$1
  while [ "$_u" != "${_u%/}" ]; do
    _u=${_u%/}
  done
  printf '%s\n' "$_u"
}
