#!/bin/sh
# Red-green tests for lib/fetch.py (stdlib urllib GET, no curl).
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
FETCH="$ROOT/lib/fetch.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; if [ -n "${SRV_PID:-}" ]; then kill "$SRV_PID" 2>/dev/null || true; fi' EXIT

# --- missing implementation is a real failure, not a typo ---
if [ ! -f "$FETCH" ]; then
  echo "FAIL: lib/fetch.py missing"
  exit 1
fi

# Local server that records the Authorization header and serves a body.
python3 - "$TMP" <<'PY' &
import json, sys, threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

workdir = Path(sys.argv[1])
state = {"auth": None, "path": None}

class H(BaseHTTPRequestHandler):
    def log_message(self, *args):
        return

    def do_GET(self):
        state["auth"] = self.headers.get("Authorization")
        state["path"] = self.path
        if self.path == "/boom":
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"nope")
            return
        body = b'{"ok":true,"models":[]}\n'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        (workdir / "seen.json").write_text(json.dumps(state))

httpd = HTTPServer(("127.0.0.1", 0), H)
port = httpd.server_address[1]
(workdir / "port").write_text(str(port))
httpd.serve_forever()
PY
SRV_PID=$!

i=0
while [ ! -f "$TMP/port" ]; do
  i=$((i + 1))
  if [ "$i" -gt 50 ]; then
    echo "FAIL: test server did not start"
    exit 1
  fi
  sleep 0.05
done
PORT=$(cat "$TMP/port")
BASE=http://127.0.0.1:$PORT

# get writes the body
python3 "$FETCH" get "$BASE/api/tags" --out "$TMP/out.json"
test -s "$TMP/out.json" || { echo "FAIL: get wrote empty file"; exit 1; }
grep -q '"ok":true' "$TMP/out.json" || { echo "FAIL: get body mismatch"; cat "$TMP/out.json"; exit 1; }

# check succeeds on 200
python3 "$FETCH" check "$BASE/api/tags"

# check fails on connection refused
if python3 "$FETCH" check http://127.0.0.1:1 >/dev/null 2>&1; then
  echo "FAIL: check should fail on closed port"
  exit 1
fi

# check fails on HTTP 500
if python3 "$FETCH" check "$BASE/boom" >/dev/null 2>&1; then
  echo "FAIL: check should fail on HTTP 500"
  exit 1
fi

# get without --out is usage error
if python3 "$FETCH" get "$BASE/api/tags" >/dev/null 2>&1; then
  echo "FAIL: get without --out should fail"
  exit 1
fi

# bearer is forwarded
python3 "$FETCH" get "$BASE/v1/models" --out "$TMP/out2.json" --bearer ollama
python3 - "$TMP/seen.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s["auth"]=="Bearer ollama", s
assert s["path"]=="/v1/models", s
print("bearer ok")
PY

echo "fetch_test ok"
