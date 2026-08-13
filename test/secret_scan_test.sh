#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
# If dist exists, scan it. Otherwise scan is skipped (make dist runs the real scan).
if [ ! -f "$ROOT/dist/install-ollama-agents.sh" ]; then
  echo "no dist yet; skip"
  exit 0
fi
sh "$ROOT/scripts/secret-scan.sh" "$ROOT/dist/install-ollama-agents.sh"
echo "secret-scan ok"
