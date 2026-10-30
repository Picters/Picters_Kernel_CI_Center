#!/system/bin/sh
# Leased charging targets. Never changes OEM protection/thermal client votes.
set -eu
MODDIR=${0%/*}
STATE=/data/adb/picters_modules_manager/charging
THERMAL=/data/adb/picters_modules_manager/thermal/session/target
SYS=/sys/kernel/picters_charging
CONF=$STATE/policy
locked=0
die() { echo "$*" >&2; exit 1; }
unlock() { if [ "$locked" = 1 ]; then rm -rf "$STATE/lock"; locked=0; fi; }
trap unlock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[ "$(id -u)" = 0 ] || die 'Root is required.'

vendor_ok() {
  [ "$(getprop ro.product.device)" = pudding ] || return 1
  [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] || return 1
  [ "$(uname -r)" = "$(cat "$MODDIR/expected-kernel")" ] || return 1
  for spec in \
    'mca_voter ceff20058204d5a7b0afbb48914621f2dba71d85c3a77d5a623dfae90d418277' \
    'mca_strategy_buckchg ab9edb92cdd5a58d38ee4ae509435ab94b42587fea8004618998e9ad1fdb851c' \
    'mca_strategy_quickchg 95f9802c72595131f7b155bd9ed05ef924dd85d819e57bc23ffdc6da0011eb8e'; do
    set -- $spec
    [ -d "/sys/module/$1" ] || return 1
    sum=$(sha256sum "/vendor_dlkm/lib/modules/$1.ko") || return 1
    [ "${sum%% *}" = "$2" ] || return 1
  done
}
prepare() {
  vendor_ok || die 'The installed MCA vendor ABI is unsupported.'
  if [ ! -e "$SYS/capabilities" ]; then
    insmod "$MODDIR/system/lib/modules/picters_charging.ko" || die 'Charging adapter could not load.'
  fi
  [ "$(cat "$SYS/capabilities")" = 'PMM_MCA_TARGET_V1 leased own_votes' ] || die 'Unsupported charging adapter API.'
}
lock() {
  mkdir -p "$STATE"
  chmod 0700 "$STATE"
  lock_attempt=0
  while ! mkdir "$STATE/lock" 2>/dev/null; do
    lock_attempt=$((lock_attempt + 1))
    owner=$(cat "$STATE/lock/owner" 2>/dev/null || true)
    case "$owner" in
      ''|*[!0-9]*) ;;
      *) if ! kill -0 "$owner" 2>/dev/null; then rm -rf "$STATE/lock"; continue; fi;;
    esac
    [ "$lock_attempt" -lt 50 ] || die 'Charging operation is busy.'
    sleep 0.1
  done
  locked=1
  printf '%s\n' "$$" > "$STATE/lock/owner"
}
read_policy() {
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || return 1
  target=$(sed -n '1p' "$CONF")
  persist=$(sed -n '2p' "$CONF")
  vendor=$(sed -n '3p' "$CONF")
  case "$target" in off|[1-9]|[1-9][0-9]|1[01][0-9]|120) ;; *) return 1;; esac
  case "$persist" in 0|1) ;; *) return 1;; esac
  [ "$vendor" = "$(getprop ro.vendor.build.fingerprint)" ] || return 1
}
thermal_off() { [ "$(cat "$THERMAL" 2>/dev/null)" = off ]; }
write_target() {
  value=$1
  [ "$value" != off ] || value=0
  printf '%s\n' "$value" > "$SYS/power_target"
}
restore_locked() {
  [ ! -e "$SYS/power_target" ] || write_target 0
  rm -f "$CONF"
}
process_identity() {
  raw=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  fields=${raw##*) }
  set -- $fields
  [ "$#" -ge 20 ] && [ "$1" != Z ] || return 1
  printf '%s %s' "$(cat /proc/sys/kernel/random/boot_id)" "${20}"
}
start_daemon() {
  # A single worker owns the refresh loop; no process is killed by PID.
  if mkdir "$STATE/daemon.lock" 2>/dev/null; then
    sh "$MODDIR/chargingctl.sh" daemon </dev/null >> "$STATE/service.log" 2>&1 &
    pid=$!
    identity=$(process_identity "$pid") || return 1
    printf '%s %s\n' "$pid" "$identity" > "$STATE/daemon.lock/owner"
  else
    pid=; boot=; born=
    read -r pid boot born < "$STATE/daemon.lock/owner" || return 1
    case "$pid" in ''|*[!0-9]*) return 1;; esac
    identity=$(process_identity "$pid" || true)
    if [ "$identity" != "$boot $born" ]; then
      rm -rf "$STATE/daemon.lock"
      start_daemon
    fi
  fi
}

case "${1:-status}" in
  api) echo PMM_CHARGING_POLICY_V1;;
  prepare) prepare;;
  status)
    prepare
    kernel_status=$(cat "$SYS/status")
    healthy=0
    case "$kernel_status" in *' error=0') healthy=1;; esac
    if read_policy && thermal_off && [ "$healthy" = 1 ]; then
      expected=$target; [ "$expected" != off ] || expected=0
      [ "${kernel_status%% *}" = "target_w=$expected" ] || healthy=0
    else healthy=0; fi
    if [ "$healthy" = 1 ]; then
      printf 'charging=1\npower_target=%s\ncharging_persist=%s\n' "$target" "$persist"
    else printf 'charging=0\npower_target=100\ncharging_persist=0\n'; fi
    printf '%s\n' "$kernel_status"
    ;;
  apply)
    target=${2:-}; persist=${3:-}
    case "$target" in off|[1-9]|[1-9][0-9]|1[01][0-9]|120) ;; *) die 'Choose 1..120 W or Off.';; esac
    case "$persist" in 0|1) ;; *) die 'Invalid persistence.';; esac
    prepare
    thermal_off || die 'Set Custom throttling to Off first.'
    lock
    previous=$(cat "$SYS/power_target")
    if ! write_target "$target"; then
      write_target "$previous" || true
      die 'Charging target was rejected.'
    fi
    if ! { printf '%s\n%s\n%s\n' "$target" "$persist" "$(getprop ro.vendor.build.fingerprint)" > "$CONF.new" && mv "$CONF.new" "$CONF"; }; then
      write_target "$previous" || true
      die 'Could not save charging target.'
    fi
    start_daemon || { restore_locked; die 'Charging worker could not start.'; }
    ;;
  restore) lock; restore_locked;;
  boot)
    rm -rf "$STATE/lock"
    lock
    # No worker survives a reboot. Recover only a previously persisted policy.
    rm -rf "$STATE/daemon.lock"
    if read_policy && [ "$persist" = 1 ] && thermal_off; then
      prepare; write_target "$target"; start_daemon
    else restore_locked; fi
    ;;
  daemon)
    # Kernel lease releases votes within 30 s even after SIGKILL or a crash.
    daemon_cleanup() {
      unlock
      cleanup_pid=
      read -r cleanup_pid cleanup_boot cleanup_born < "$STATE/daemon.lock/owner" 2>/dev/null || true
      [ "$cleanup_pid" != "$$" ] || rm -rf "$STATE/daemon.lock"
    }
    trap daemon_cleanup EXIT
    while [ -f "$MODDIR/chargingctl.sh" ]; do
      if mkdir "$STATE/lock" 2>/dev/null; then
        locked=1; printf '%s\n' "$$" > "$STATE/lock/owner"
        if [ ! -f "$CONF" ]; then
          rm -rf "$STATE/daemon.lock"; unlock; break
        fi
        if ! read_policy || ! thermal_off || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
          restore_locked; rm -rf "$STATE/daemon.lock"; unlock; break
        fi
        if ! write_target "$target"; then
          restore_locked; rm -rf "$STATE/daemon.lock"; unlock; break
        fi
        unlock
      fi
      sleep 2
    done
    ;;
  *) die 'Unknown charging command.';;
esac
