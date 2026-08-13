#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
# --catalog-file path through install.sh --dry-run
out=$(sh "$ROOT/install.sh" --catalog-file "$ROOT/testdata/mini-tags.json" --tools=claude --dry-run --verbose 2>&1)
printf '%s\n' "$out" | grep -q 'haiku=granite4.1:8b' || { echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q 'sonnet=qwen2.5-coder:14b' || { echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q 'completion, 1 skip' || { echo "$out"; exit 1; }
echo "discover/dry-run ok"
