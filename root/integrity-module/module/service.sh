#!/system/bin/sh
PATH=/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk:/system/bin:/system/xbin
export PATH
MODPATH="${0%/*}"
TS_DIR=/data/adb/tricky_store
mkdir -p "$TS_DIR" 2>/dev/null

bootlog() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$TS_DIR/integrity.log" 2>/dev/null
}

bootlog "service.sh start, module $MODPATH"

if [ -f "$MODPATH/pif-service.sh" ]; then
    . "$MODPATH/pif-service.sh"
    bootlog "pif service stage done"
fi

INTEGRITY_BIN="$MODPATH/bin"
if [ -f "$INTEGRITY_BIN/keybox.sh" ]; then
    . "$INTEGRITY_BIN/keybox.sh"
    keybox_auto_apply
fi

sh "$MODPATH/bin/fix-persist.sh" >/dev/null 2>&1

chmod 755 "$MODPATH/daemon" "$MODPATH/machikado" "$MODPATH/mazoku" 2>/dev/null
chmod 644 "$MODPATH/libtricky_store.so" "$MODPATH/service.apk" 2>/dev/null

if [ -x "$MODPATH/daemon" ]; then
    bootlog "starting the TrickyStore daemon loop from $MODPATH"
    (
        cd "$MODPATH" || exit 1
        while :; do
            ./daemon
            sleep 2
        done
    ) &
fi

if [ -x "$MODPATH/bin/boot-verdict.sh" ]; then
    nohup sh "$MODPATH/bin/boot-verdict.sh" >/dev/null 2>&1 &
fi
