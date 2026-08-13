#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
fail=0
for t in \
  "$ROOT/test/posix_lint.sh" \
  "$ROOT/test/discover_test.sh" \
  "$ROOT/test/classify_test.sh" \
  "$ROOT/test/claude_merge_test.sh" \
  "$ROOT/test/junie_merge_test.sh" \
  "$ROOT/test/toml_upsert_unit.sh" \
  "$ROOT/test/grok_merge_test.sh" \
  "$ROOT/test/cli_test.sh" \
  "$ROOT/test/secret_scan_test.sh"
do
  if [ -x "$t" ] || [ -f "$t" ]; then
    echo "== $(basename "$t") =="
    if sh "$t"; then
      echo "ok"
    else
      echo "FAIL $t"
      fail=1
    fi
  fi
done
exit $fail
