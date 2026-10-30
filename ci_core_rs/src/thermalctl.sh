#!/system/bin/sh
# Root-side thermal file transaction. No charging controls are changed here.
set -eu
umask 077
STATE=/data/adb/picters_modules_manager/thermal
CONFIG=/data/vendor/thermal/config
TX=/data/vendor/thermal/.picters-transaction
STAGE="$STATE/stage"
SESSION="$STATE/session"
LOCK="$STATE/lock"
locked=0
committing=0

die() { printf '%s\n' "$*" >&2; exit 1; }
fingerprint() { getprop ro.vendor.build.fingerprint; }
restart_if_running() {
  [ "$(getprop init.svc.mi_thermald)" = running ] || return 0
  old_pid=$(pidof mi_thermald)
  setprop ctl.restart mi_thermald || return 1
  count=0
  while [ "$count" -lt 30 ]; do
    new_pid=$(pidof mi_thermald 2>/dev/null || true)
    if [ "$(getprop init.svc.mi_thermald)" = running ] &&
       [ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ]; then
      return 0
    fi
    count=$((count + 1))
    sleep 0.1
  done
  return 1
}

recover() {
  [ -d "$TX" ] || return 0
  if [ -d "$TX/before" ]; then
    if [ -e "$CONFIG" ]; then
      [ ! -e "$TX/failed" ] || return 1
      mv "$CONFIG" "$TX/failed" || return 1
    fi
    mv "$TX/before" "$CONFIG" || return 1
  elif [ -f "$TX/config-was-absent" ]; then
    if [ -e "$CONFIG" ] && [ -f "$TX/swapped" ]; then
      [ ! -e "$TX/failed" ] || return 1
      mv "$CONFIG" "$TX/failed" || return 1
    fi
  fi
  if [ -f "$TX/session-ready" ]; then
    rm -rf "$SESSION"
    [ ! -d "$TX/session-before" ] || cp -a "$TX/session-before" "$SESSION"
  fi
  # Keep failed output for inspection; never delete an unexplained live tree.
  if [ -d "$TX/failed" ]; then
    failed="$STATE/failed-$(date +%s)-$$"
    mv "$TX/failed" "$failed" || return 1
  fi
  rm -rf "$TX"
  restart_if_running
}

finish() {
  rc=$?
  trap - 0 INT TERM
  if [ "$committing" = 1 ]; then
    recover || printf '%s\n' 'Thermal recovery needs attention; backup retained.' >&2
  fi
  if [ "$locked" = 1 ]; then rm -f "$LOCK/boot"; rmdir "$LOCK" 2>/dev/null || true; fi
  exit "$rc"
}

lock() {
  mkdir -p "$STATE"
  [ ! -L "$STATE" ] && [ ! -L "$CONFIG" ] && [ ! -L "$TX" ] || die 'Symlinked thermal storage is unsupported.'
  [ ! -e "$CONFIG" ] || [ -d "$CONFIG" ] || die 'Thermal configuration path is not a directory.'
  if [ "${1:-}" = boot ] && [ -r "$LOCK/boot" ] &&
     [ "$(cat "$LOCK/boot")" != "$(cat /proc/sys/kernel/random/boot_id)" ]; then
    rm -f "$LOCK/boot"
    rmdir "$LOCK" 2>/dev/null || true
  fi
  mkdir "$LOCK" 2>/dev/null || die 'Thermal operation is already locked.'
  locked=1
  cat /proc/sys/kernel/random/boot_id > "$LOCK/boot"
  trap finish 0
  trap 'exit 130' INT
  trap 'exit 143' TERM
  recover || die 'Previous thermal transaction could not be recovered.'
}

validate_manifest() {
  manifest=$1
  [ -s "$manifest" ] || die 'Missing thermal manifest.'
  entries=0
  while read -r digest name extra; do
    [ -z "${extra:-}" ] || die 'Invalid thermal manifest columns.'
    [ "${#digest}" = 64 ] || die 'Invalid thermal digest.'
    case "$digest" in *[!0-9a-f]*) die 'Invalid thermal digest.';; esac
    case "$name" in thermal-*.conf) ;; *) die 'Invalid thermal filename.';; esac
    case "$name" in *[!a-z0-9.-]*|*..*) die 'Invalid thermal filename.';; esac
    entries=$((entries + 1))
    [ "$entries" -le 256 ] || die 'Too many thermal files.'
  done < "$manifest"
  [ "$entries" -gt 0 ] || die 'Empty thermal manifest.'
  [ "$(awk '{print $2}' "$manifest" | sort -u | wc -l)" -eq "$entries" ] || die 'Duplicate thermal filename.'
}

verify_active() {
  [ -f "$SESSION/active.sha256" ] || return 0
  validate_manifest "$SESSION/active.sha256"
  while read -r digest name; do
    [ -f "$CONFIG/$name" ] && [ ! -L "$CONFIG/$name" ] || die 'A managed thermal file was removed or replaced.'
  done < "$SESSION/active.sha256"
  (cd "$CONFIG" && sha256sum -c "$SESSION/active.sha256") >/dev/null || die 'Thermal files changed outside the app; preserving them.'
}

begin_transaction() {
  mkdir "$TX"
  if [ -d "$SESSION" ]; then cp -a "$SESSION" "$TX/session-before"; fi
  : > "$TX/session-ready"
  if [ -d "$CONFIG" ]; then cp -a "$CONFIG" "$TX/next";
  else
    mkdir "$TX/next"
    chown 0:1000 "$TX/next"
    chmod 0750 "$TX/next"
    : > "$TX/config-was-absent"
  fi
  committing=1
}

swap_and_restart() {
  if [ -d "$CONFIG" ]; then mv "$CONFIG" "$TX/before"; fi
  # Marker precedes the rename so SIGKILL after rename remains recoverable.
  : > "$TX/swapped"
  mv "$TX/next" "$CONFIG"
  restorecon -RF "$CONFIG"
  restart_if_running || die 'Thermal service restart failed.'
}

apply_profile() {
  [ "$(getprop ro.product.device)" = pudding ] || die 'Unsupported device.'
  [ "$(getprop init.svc.mi_thermald)" = running ] || die 'Xiaomi thermal service is not running.'
  [ -f "$STAGE/vendor-fingerprint" ] &&
    [ "$(cat "$STAGE/vendor-fingerprint")" = "$(fingerprint)" ] || die 'Thermal vendor fingerprint mismatch.'
  target=$(cat "$STAGE/target")
  case "$target" in off|2[5-9]|[3-5][0-9]|6[0-5]) ;; *) die 'Invalid thermal target.';; esac
  persist=$(cat "$STAGE/persist")
  case "$persist" in 0|1) ;; *) die 'Invalid thermal persistence.';; esac
  validate_manifest "$STAGE/manifest.sha256"
  while read -r digest name; do
    file="$STAGE/files/$name"
    [ -f "$file" ] && [ ! -L "$file" ] || die 'Missing staged thermal file.'
    size=$(stat -c %s "$file")
    [ "$size" -gt 0 ] && [ "$size" -le 2097152 ] &&
      [ "$((size % 16))" = 0 ] || die 'Invalid encrypted thermal file size.'
  done < "$STAGE/manifest.sha256"
  (cd "$STAGE/files" && sha256sum -c "$STAGE/manifest.sha256") >/dev/null || die 'Staged thermal checksum mismatch.'
  verify_active
  if [ -f "$SESSION/active.sha256" ]; then
    [ "$(cat "$SESSION/vendor-fingerprint")" = "$(fingerprint)" ] || die 'Restore the previous firmware profile first.'
    [ "$(awk '{print $2}' "$SESSION/active.sha256" | sort)" = \
      "$(awk '{print $2}' "$STAGE/manifest.sha256" | sort)" ] || die 'Thermal scenario set changed; restore first.'
  fi
  begin_transaction
  if [ ! -f "$SESSION/active.sha256" ]; then
    rm -rf "$SESSION"
    mkdir -p "$SESSION/original"
    while read -r digest name; do
      if [ -e "$CONFIG/$name" ]; then
        [ -f "$CONFIG/$name" ] && [ ! -L "$CONFIG/$name" ] || die 'Unsupported original thermal file.'
        cp -a "$CONFIG/$name" "$SESSION/original/$name"
      fi
    done < "$STAGE/manifest.sha256"
  fi
  while read -r digest name; do
    cp "$STAGE/files/$name" "$TX/next/$name"
    chown 0:1000 "$TX/next/$name"
    chmod 0640 "$TX/next/$name"
  done < "$STAGE/manifest.sha256"
  swap_and_restart
  cp "$STAGE/manifest.sha256" "$SESSION/active.sha256"
  cp "$STAGE/vendor-fingerprint" "$SESSION/vendor-fingerprint"
  printf '%s\n' "$target" > "$SESSION/target"
  printf '%s\n' "$persist" > "$SESSION/persist"
  rm -rf "$TX"
  committing=0
  printf '%s\n' 'files-installed=1' 'service-restarted=1' 'behavior-verified=0'
}

restore_profile() {
  [ -f "$SESSION/active.sha256" ] || { printf '%s\n' 'stock=1'; return 0; }
  verify_active
  begin_transaction
  while read -r digest name; do
    if [ -f "$SESSION/original/$name" ]; then
      cp -a "$SESSION/original/$name" "$TX/next/$name"
    else rm -f "$TX/next/$name"; fi
  done < "$SESSION/active.sha256"
  swap_and_restart
  rm -rf "$SESSION"
  rm -rf "$TX"
  committing=0
  printf '%s\n' 'stock=1'
}

[ "$(id -u)" = 0 ] || die 'Root is required.'
case "${1:-}" in
  api) printf '%s\n' 'PMM_THERMAL_FILES_V1';;
  status)
    [ ! -d "$TX" ] || die 'Thermal recovery is pending; reboot first.'
    if [ -f "$SESSION/active.sha256" ]; then
      printf 'target=%s\npersist=%s\n' "$(cat "$SESSION/target")" "$(cat "$SESSION/persist")"
    else printf '%s\n' 'target=stock' 'persist=0'; fi
    ;;
  persist)
    case "${2:-}" in 0|1) ;; *) die 'Expected persistence 0 or 1.';; esac
    lock
    if [ -f "$SESSION/active.sha256" ]; then
      verify_active
      printf '%s\n' "$2" > "$SESSION/.persist"
      mv "$SESSION/.persist" "$SESSION/persist"
    fi
    ;;
  apply) lock; apply_profile;;
  restore) lock; restore_profile;;
  boot)
    lock boot
    if [ -f "$SESSION/active.sha256" ]; then
      if [ "$(cat "$SESSION/persist")" != 1 ] ||
         [ "$(cat "$SESSION/vendor-fingerprint")" != "$(fingerprint)" ]; then
        restore_profile
      else verify_active; fi
    fi
    ;;
  *) die 'Usage: thermalctl.sh api|status|apply|restore|persist 0/1|boot';;
esac
