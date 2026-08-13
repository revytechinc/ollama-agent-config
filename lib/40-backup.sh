cba_stamp() {
  date +%Y%m%d-%H%M%S
}

cba_prune_old_backups() {
  _dir=$1
  _glob=$2
  _n=0
  # newest 20 kept; never delete *.broken
  ls -1t "$_dir"/$_glob 2>/dev/null | while read -r f; do
    case "$f" in
      *.broken) continue ;;
    esac
    _n=$((_n + 1))
    if [ "$_n" -gt 20 ]; then
      rm -f "$f"
    fi
  done
}

cba_backup_file() {
  _src=$1
  _destdir=$2
  _mode=${3:-644}
  [ -f "$_src" ] || return 0
  mkdir -p -m 755 "$_destdir"
  _dst="$_destdir/$(basename "$_src").$(cba_stamp)"
  if [ "$_mode" = "600" ]; then
    mkdir -p -m 700 "$_destdir"
    python3 -c '
import os,sys,shutil
src,dst=sys.argv[1],sys.argv[2]
fd=os.open(dst, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
os.close(fd)
shutil.copyfile(src,dst)
os.chmod(dst, 0o600)
' "$_src" "$_dst"
  else
    cp -p "$_src" "$_dst"
  fi
  printf '%s\n' "$_dst"
}

cba_backup_tar() {
  _srcdir=$1
  _destdir=$2
  [ -d "$_srcdir" ] || return 0
  mkdir -p "$_destdir"
  _dst="$_destdir/models.$(cba_stamp).tar"
  tar -cf "$_dst" -C "$_srcdir" . 2>/dev/null || tar -cf "$_dst" -C "$_srcdir" .
  printf '%s\n' "$_dst"
}
