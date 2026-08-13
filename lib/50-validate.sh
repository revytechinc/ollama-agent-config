cba_endpoint_ok() {
  _host=$1
  if curl -fsS --connect-timeout 3 --max-time 15 -o /dev/null "$_host/api/tags"; then
    return 0
  fi
  curl -fsS --connect-timeout 3 --max-time 15 -o /dev/null "$_host/v1/models"
}

cba_bin_version() {
  _bin=$1
  command -v "$_bin" >/dev/null 2>&1 || return 1
  "$_bin" --version >/dev/null 2>&1 || "$_bin" -v >/dev/null 2>&1
}
