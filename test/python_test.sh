#!/bin/sh
# Installer must refuse to run without python3 and tell the user how to install it.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# PATH with no python3 (this host keeps it in /usr/local/bin).
PATH="/bin:/usr/bin"
export PATH

# Repo-mode entry (lib/ present).
err=$TMP/err1
if sh "$ROOT/install.sh" --dry-run --catalog-file "$ROOT/testdata/mini-tags.json" --tools=claude 2>"$err"; then
  echo "FAIL: install.sh ran without python3"
  exit 1
fi
grep -q 'python3 is not installed' "$err" || { echo "FAIL: missing 'python3 is not installed'"; cat "$err"; exit 1; }
grep -q 'pkg install python3' "$err" || grep -qi 'install python3' "$err" || {
  echo "FAIL: no install hint"; cat "$err"; exit 1
}

# Piped/bootstrap entry (no lib/).
cp "$ROOT/install.sh" "$TMP/install.sh"
err=$TMP/err2
if sh "$TMP/install.sh" --dry-run 2>"$err"; then
  echo "FAIL: bootstrap ran without python3"
  exit 1
fi
grep -q 'python3 is not installed' "$err" || { echo "FAIL: bootstrap missing message"; cat "$err"; exit 1; }
grep -q 'pkg install python3' "$err" || grep -qi 'install python3' "$err" || {
  echo "FAIL: bootstrap no install hint"; cat "$err"; exit 1
}

echo "python_test ok"
