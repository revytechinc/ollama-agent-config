#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
DESTDIR=${DESTDIR:-/usr/local/www/install}
echo "Installing to $DESTDIR (needs write access)"
install -d -m 755 "$DESTDIR"
install -m 644 "$ROOT/dist/install-ollama-agent-config.sh" "$DESTDIR/install-ollama-agent-config.sh"
install -m 644 "$ROOT/dist/install-ollama-agent-config.sh.sha256" "$DESTDIR/install-ollama-agent-config.sh.sha256"
SNIP=/usr/local/etc/nginx/snippets/install-scripts.conf
if [ -w /usr/local/etc/nginx/snippets ] || [ "$(id -u)" -eq 0 ]; then
  install -m 644 "$ROOT/maint/nginx-install-scripts.conf" "$SNIP"
  echo "installed $SNIP"
  echo "If nginx.conf lacks the include, add after packages.conf:"
  echo "        include /usr/local/etc/nginx/snippets/install-scripts.conf;"
  echo "Then: nginx -t && service nginx reload"
else
  echo "not root: wrote files only. Copy maint/nginx-install-scripts.conf yourself."
fi
