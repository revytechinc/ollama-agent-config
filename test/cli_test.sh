#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
sh "$ROOT/install.sh" --help | grep -q 'dry-run'
# checksum file format after make dist
if [ -f "$ROOT/dist/install-ollama-agents.sh" ]; then
  tmp=$(mktemp -d)
  cp "$ROOT/dist/install-ollama-agents.sh" "$tmp/"
  cp "$ROOT/dist/install-ollama-agents.sh.sha256" "$tmp/"
  ( cd "$tmp" && sha256sum -c install-ollama-agents.sh.sha256 )
  rm -rf "$tmp"
  echo "sha256sum -c ok"
else
  echo "dist missing; skip checksum until make dist"
fi
echo "cli help ok"
