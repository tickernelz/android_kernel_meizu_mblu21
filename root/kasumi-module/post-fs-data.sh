#!/system/bin/sh
LOG=/data/adb/ksu/log/kasumi.log
mkdir -p /data/adb/ksu/log
[ -e /sys/module/kasumi_lkm ] && exit 0
KO=/data/adb/modules/kasumi_lkm/kasumi_lkm.ko
for other in susfs_guard_lkm pathmask procguard nomount hybridmount; do
  if [ -e "/sys/module/$other" ]; then
    echo "$(date '+%F %T') skipped: $other is loaded and Kasumi refuses to run beside it" >> "$LOG"
    exit 0
  fi
done
echo "$(date '+%F %T') loading $KO" >> "$LOG"
/data/adb/ksud insmod "$KO" >> "$LOG" 2>&1
echo "$(date '+%F %T') rc=$? present=$([ -e /sys/module/kasumi_lkm ] && echo yes || echo no)" >> "$LOG"
