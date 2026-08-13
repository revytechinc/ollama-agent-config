#!/bin/sh
# Scan a built dist script for host secrets. See design Key Decision 25.
set -eu
f=$1
[ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
fail=0
if grep -F '/usr/local/etc/nginx/conf.d/ollama.conf' "$f" >/dev/null 2>&1; then
  echo "secret-scan: nginx ollama.conf path" >&2
  fail=1
fi
if grep -F 'proxy_set_header Authorization' "$f" >/dev/null 2>&1; then
  echo "secret-scan: proxy_set_header Authorization" >&2
  fail=1
fi
if grep -E 'Basic [A-Za-z0-9+/=]{16,}' "$f" >/dev/null 2>&1; then
  echo "secret-scan: Basic token" >&2
  fail=1
fi
exit $fail
