cba_tool_grok() {
  command -v grok >/dev/null 2>&1 && return 0
  command -v grok-build >/dev/null 2>&1
}

cba_grok_warn_fragment() {
  _f=$HOME/.grok/config.models.fragment.toml
  if [ -f "$_f" ]; then
    _mode=$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$_f")
    cba_log "warn: $_f exists (mode $_mode) and is not loaded by Grok; it may contain secrets. Not rewriting."
  fi
}

cba_grok_write() {
  _file=${CBA_GROK_CONFIG:-$HOME/.grok/config.toml}
  [ -f "$_file" ] || cba_die "missing $_file"
  set -- upsert --file "$_file" --catalog "$CBA_CLASS" --host "$CBA_HOST"
  if [ "$CBA_SET_GROK_DEFAULT" -eq 1 ]; then
    _slug=$(python3 -c 'import sys; sys.path.insert(0,sys.argv[1]); from catalog import grok_slug; print(grok_slug(sys.argv[2]))' "${CBA_ROOT:-$CBA_WORKDIR}/lib" "$CBA_ROLE_SONNET")
    set -- "$@" --set-default "$_slug"
  fi
  cba_py toml_upsert.py "$@"
}

cba_grok_validate() {
  _file=${CBA_GROK_CONFIG:-$HOME/.grok/config.toml}
  cba_py toml_upsert.py check --file "$_file" --catalog "$CBA_CLASS" --host "$CBA_HOST" || return 1
  if ! cba_endpoint_ok "$CBA_HOST"; then
    cba_log "warn: endpoint check failed"
    [ "$CBA_STRICT" -eq 1 ] && return 1
  fi
  return 0
}

cba_grok_backup() {
  _file=${CBA_GROK_CONFIG:-$HOME/.grok/config.toml}
  mkdir -p -m 700 "$HOME/.grok/backups"
  cba_backup_file "$_file" "$HOME/.grok/backups" 600
}

cba_grok_run() {
  cba_grok_warn_fragment
  if [ "$CBA_VALIDATE_ONLY" -eq 1 ]; then
    cba_grok_validate
    return $?
  fi
  CBA_GROK_BACKUP=$(cba_grok_backup)
  cba_grok_write || return 1
  cba_grok_validate
}

cba_grok_prune() {
  _file=${CBA_GROK_CONFIG:-$HOME/.grok/config.toml}
  cba_py toml_upsert.py upsert --file "$_file" --catalog "$CBA_CLASS" --host "$CBA_HOST" --prune
}
