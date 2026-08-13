#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fail=0
# Dist file is generated; lint source only. Allow `source` only if we never use it.
for f in "$ROOT/install.sh" "$ROOT/lib"/*.sh "$ROOT/adapters"/*.sh "$ROOT/wrappers"/*.sh; do
  [ -f "$f" ] || continue
  if grep -n '\[\[' "$f" >/dev/null 2>&1; then
    echo "bashism [[ in $f"; fail=1
  fi
  if grep -n '[[:space:]]source ' "$f" >/dev/null 2>&1; then
    echo "source in $f"; fail=1
  fi
  if grep -n 'PIPESTATUS' "$f" >/dev/null 2>&1; then
    echo "PIPESTATUS in $f"; fail=1
  fi
  if grep -n '/dev/fd/' "$f" >/dev/null 2>&1; then
    echo "/dev/fd in $f"; fail=1
  fi
  if grep -n 'echo -n' "$f" >/dev/null 2>&1; then
    echo "echo -n in $f"; fail=1
  fi
  if grep -n '^function ' "$f" >/dev/null 2>&1; then
    echo "function keyword in $f"; fail=1
  fi
done
exit $fail
