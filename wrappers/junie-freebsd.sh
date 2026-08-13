#!/bin/sh
# FreeBSD launcher for JetBrains Junie.
# Official shims ship with #!/bin/bash, which does not exist on FreeBSD.
# This wrapper rewrites that shebang and then runs the official shim with
# /usr/local/bin/bash so Linuxulator still executes the bundled Linux binary.

set -eu

JUNIE_SHIM="${JUNIE_SHIM:-$HOME/.local/bin/junie}"
JUNIE_DATA="${JUNIE_DATA:-$HOME/.local/share/junie}"
BASH_BIN="${BASH_BIN:-/usr/local/bin/bash}"

fix_shebang() {
  _f="$1"
  [ -f "$_f" ] || return 0
  _first=$(head -n 1 "$_f" 2>/dev/null || true)
  if [ "$_first" = "#!/bin/bash" ]; then
    _tmp="${_f}.shebang.tmp.$$"
    { echo '#!/usr/bin/env bash'; tail -n +2 "$_f"; } > "$_tmp" && mv "$_tmp" "$_f" && chmod +x "$_f"
  fi
}

if [ ! -x "$BASH_BIN" ]; then
  echo "junie: bash not found at $BASH_BIN (pkg install bash)" >&2
  exit 1
fi

if [ ! -f "$JUNIE_SHIM" ]; then
  echo "junie: official shim missing at $JUNIE_SHIM" >&2
  exit 1
fi

fix_shebang "$JUNIE_SHIM"
if [ -d "$JUNIE_DATA/versions" ]; then
  for _wrapper in "$JUNIE_DATA/versions"/*/junie; do
    fix_shebang "$_wrapper"
  done
fi

exec "$BASH_BIN" "$JUNIE_SHIM" "$@"
