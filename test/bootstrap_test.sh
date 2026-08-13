#!/bin/sh
# Piped install.sh must fetch dist/, verify sha256, then exec.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
sh "$ROOT/scripts/make-dist.sh" >/dev/null
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; if [ -n "${SRV_PID:-}" ]; then kill "$SRV_PID" 2>/dev/null || true; fi' EXIT

python3 - "$ROOT" "$TMP" <<'PY' &
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

root = Path(sys.argv[1])
workdir = Path(sys.argv[2])

class H(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(root), **kwargs)

    def log_message(self, *args):
        return

httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
(workdir / "port").write_text(str(httpd.server_address[1]))
httpd.serve_forever()
PY
SRV_PID=$!

i=0
while [ ! -f "$TMP/port" ]; do
  i=$((i + 1))
  [ "$i" -gt 50 ] && { echo "FAIL: server"; exit 1; }
  sleep 0.05
done
PORT=$(cat "$TMP/port")

# Only the entrypoint — no lib/ — same as curl | sh from an empty cwd.
cp "$ROOT/install.sh" "$TMP/install.sh"
mkdir -p "$TMP/empty"
cd "$TMP/empty"

out=$(CBA_INSTALL_BASE="http://127.0.0.1:$PORT" sh "$TMP/install.sh" --dry-run --tools=claude --catalog-file "$ROOT/testdata/mini-tags.json" 2>&1) || {
  echo "$out"
  echo "FAIL: bootstrap dry-run"
  exit 1
}
printf '%s\n' "$out" | grep -q 'haiku=granite4.1:8b' || { echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q 'dry-run: no files written' || { echo "$out"; exit 1; }

# Tamper checksum → must refuse
bad=$(mktemp -d)
python3 - "$ROOT" "$bad" <<'PY' &
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from functools import partial

root = Path(sys.argv[1])
workdir = Path(sys.argv[2])

class H(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(root), **kwargs)
    def log_message(self, *args):
        return
    def do_GET(self):
        if self.path.endswith(".sha256"):
            body = b"0" * 64 + b"  install-ollama-agent-config.sh\n"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        return super().do_GET()

httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
(workdir / "port").write_text(str(httpd.server_address[1]))
httpd.serve_forever()
PY
BAD_PID=$!
trap 'rm -rf "$TMP" "$bad"; kill "$SRV_PID" "$BAD_PID" 2>/dev/null || true' EXIT
i=0
while [ ! -f "$bad/port" ]; do
  i=$((i + 1))
  [ "$i" -gt 50 ] && { echo "FAIL: bad server"; exit 1; }
  sleep 0.05
done
BPORT=$(cat "$bad/port")
if CBA_INSTALL_BASE="http://127.0.0.1:$BPORT" sh "$TMP/install.sh" --dry-run 2>"$TMP/err"; then
  echo "FAIL: tampered checksum was accepted"
  exit 1
fi
grep -q 'checksum mismatch' "$TMP/err" || { echo "FAIL: expected checksum mismatch"; cat "$TMP/err"; exit 1; }

echo "bootstrap_test ok"
