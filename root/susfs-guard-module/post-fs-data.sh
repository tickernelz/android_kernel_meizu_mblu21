#!/system/bin/sh
LOG=/data/adb/ksu/log/susfs_guard.log
mkdir -p /data/adb/ksu/log
[ -e /sys/module/susfs_guard_lkm ] && exit 0
KO=/data/adb/modules/susfs_guard_lkm/susfs_guard_lkm.ko
echo "$(date '+%F %T') loading $KO" >> "$LOG"
/data/adb/ksud insmod "$KO" >> "$LOG" 2>&1
echo "$(date '+%F %T') rc=$? present=$([ -e /sys/module/susfs_guard_lkm ] && echo yes || echo no)" >> "$LOG"
