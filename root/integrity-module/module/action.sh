#!/system/bin/sh
MODPATH="${0%/*}"
exec sh "$MODPATH/bin/integrity.sh" status
