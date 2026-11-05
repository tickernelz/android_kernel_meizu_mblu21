#!/system/bin/sh
MODPATH="${0%/*}"
rm -f /data/adb/tricky_store/integrity.log
rm -f "$MODPATH/pif.prop" "$MODPATH/custom.pif.prop"
