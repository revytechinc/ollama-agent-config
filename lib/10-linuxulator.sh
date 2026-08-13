cba_linuxulator_ok() {
  [ "$(uname -s)" = "FreeBSD" ] || return 0
  if [ ! -d /compat/linux/proc ]; then
    cba_log "warn: /compat/linux/proc missing"
    return 1
  fi
  if ! mount | grep -q 'linprocfs on /compat/linux/proc'; then
    cba_log "warn: linprocfs not mounted on /compat/linux/proc"
    return 1
  fi
  if [ ! -x /compat/linux/lib64/ld-linux-x86-64.so.2 ]; then
    cba_log "warn: linux ld.so missing"
    return 1
  fi
  return 0
}
