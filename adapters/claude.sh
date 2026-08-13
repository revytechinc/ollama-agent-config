cba_tool_claude() {
  command -v claude >/dev/null 2>&1 && return 0
  [ -x /usr/local/libexec/claude ]
}

cba_claude_env_json() {
  python3 -c '
import json,sys
host,haiku,sonnet,opus,fable=sys.argv[1:6]
opus_name=opus.replace(":latest","")
print(json.dumps({
  "ANTHROPIC_AUTH_TOKEN":"ollama",
  "ANTHROPIC_API_KEY":"",
  "ANTHROPIC_BASE_URL":host,
  "ANTHROPIC_MODEL":sonnet,
  "ANTHROPIC_DEFAULT_HAIKU_MODEL":haiku,
  "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME":haiku,
  "ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION":"Fast local Ollama (Haiku)",
  "ANTHROPIC_DEFAULT_SONNET_MODEL":sonnet,
  "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME":sonnet,
  "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION":"Local Ollama coder (Sonnet)",
  "ANTHROPIC_DEFAULT_OPUS_MODEL":opus,
  "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME":opus_name,
  "ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION":"Large local Ollama coder (Opus)",
  "ANTHROPIC_DEFAULT_FABLE_MODEL":fable,
  "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME":fable,
  "ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION":"Newest local Ollama (Fable)",
  "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY":"1",
  "API_TIMEOUT_MS":"1200000",
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1",
  "DISABLE_TELEMETRY":"1",
  "DISABLE_ERROR_REPORTING":"1",
  "DISABLE_PROMPT_CACHING":"1",
}))
' "$CBA_HOST" "$CBA_ROLE_HAIKU" "$CBA_ROLE_SONNET" "$CBA_ROLE_OPUS" "$CBA_ROLE_FABLE"
}

cba_claude_write() {
  _file=${CBA_CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
  mkdir -p "$(dirname "$_file")"
  cba_claude_env_json > "$CBA_WORKDIR/claude-env.json"
  cba_py json_util.py merge-claude --file "$_file" --env-json "$CBA_WORKDIR/claude-env.json" --models-json "$CBA_CLASS"
}

cba_claude_validate() {
  _file=${CBA_CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
  cba_py json_util.py check --file "$_file" --schema claude || return 1
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
comp=json.load(open(sys.argv[2]))["completion"]
am=d.get("availableModels") or []
missing=[n for n in comp if n not in am]
if missing:
    print("availableModels missing", missing[:5], file=sys.stderr)
    sys.exit(1)
skip=json.load(open(sys.argv[2]))["skip"]
bad=[n for n in am if n in skip]
if bad:
    print("availableModels has skip-class", bad, file=sys.stderr)
    sys.exit(1)
' "$_file" "$CBA_CLASS" || return 1
  if ! cba_endpoint_ok "$CBA_HOST"; then
    cba_log "warn: endpoint check failed for $CBA_HOST"
    [ "$CBA_STRICT" -eq 1 ] && return 1
  fi
  if cba_tool_claude; then
    claude --version >/dev/null 2>&1 || cba_log "warn: claude --version failed"
  elif [ "$CBA_STRICT" -eq 1 ]; then
    return 1
  fi
  return 0
}

cba_claude_backup() {
  _file=${CBA_CLAUDE_SETTINGS:-$HOME/.claude/settings.json}
  cba_backup_file "$_file" "$HOME/.claude/backups" 644
}

cba_claude_run() {
  if [ "$CBA_VALIDATE_ONLY" -eq 1 ]; then
    cba_claude_validate
    return $?
  fi
  CBA_CLAUDE_BACKUP=$(cba_claude_backup)
  cba_claude_write || return 1
  cba_claude_validate
}

cba_claude_prune() {
  return 0
}
