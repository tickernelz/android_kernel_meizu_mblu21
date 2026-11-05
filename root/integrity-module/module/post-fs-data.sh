#!/system/bin/sh
MODPATH="${0%/*}"
if [ -f "$MODPATH/pif-post-fs-data.sh" ]; then
    . "$MODPATH/pif-post-fs-data.sh"
fi
sh "$MODPATH/bin/fix-persist.sh"
