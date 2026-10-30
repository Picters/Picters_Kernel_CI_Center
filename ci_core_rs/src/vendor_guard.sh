# Check installed vendor modules, independent of the Android system SDK.
# KMI identity is a compatibility filter, not a complete symbol-CRC audit.
picters_vendor_seen=0
picters_vendor_dirs='/vendor_dlkm/lib/modules /vendor/lib/modules /odm_dlkm/lib/modules /odm/lib/modules'
picters_check_vendor_module() {
  [ -f "$1" ] || return 0
  picters_vendor_magic=$(strings "$1" 2>/dev/null | sed -n 's/^vermagic=//p' | head -n 1)
  [ -n "$picters_vendor_magic" ] || abort 'Cannot read vendor module vermagic; vendor compatibility could not be verified'
  picters_vendor_release=${picters_vendor_magic%% *}
  case "$picters_vendor_release" in
    @VENDOR_RELEASE_PATTERN@) ;;
    *) abort "Incompatible vendor KMI: $picters_vendor_release; expected @VENDOR_KMI@" ;;
  esac
  picters_vendor_seen=$((picters_vendor_seen + 1))
}
# Prefer vendor Wi-Fi modules, never the system/GKI modules supplied by this pack.
for picters_vendor_dir in $picters_vendor_dirs; do
  picters_check_vendor_module "$picters_vendor_dir/cfg80211.ko"
  picters_check_vendor_module "$picters_vendor_dir/qca_cld3_peach_v2.ko"
done
# Other vendor layouts may have neither Wi-Fi anchor. Inspect one vendor module.
if [ "$picters_vendor_seen" -eq 0 ]; then
  for picters_vendor_dir in $picters_vendor_dirs; do
    for picters_vendor_module in "$picters_vendor_dir/"*.ko; do
      [ -f "$picters_vendor_module" ] || continue
      picters_check_vendor_module "$picters_vendor_module"
      break 2
    done
  done
fi
[ "$picters_vendor_seen" -gt 0 ] || abort 'Vendor modules unavailable; mount vendor/vendor_dlkm before installing'
