#!/system/bin/sh
PATH=/data/adb/ksu/bin:/data/adb/ap/bin:/data/adb/magisk:$PATH
export PATH
ROOT=${INTEGRITY_ROOT:-}
MODPATH="${0%/*}"
TS_DIR=$ROOT/data/adb/tricky_store
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
    if [ "$(conf_get auto_keybox)" = 1 ] && [ -f "$INTEGRITY_BIN/keybox-fetch.sh" ] &&
        { [ -n "$(conf_get keybox_url)" ] || [ -n "$(conf_get keybox_file)" ]; }; then
        sh "$INTEGRITY_BIN/keybox-fetch.sh" heal
    fi
fi

if [ "$(conf_get auto_keybox)" = 1 ] && [ -f "$INTEGRITY_BIN/keybox-fetch.sh" ] &&
    { [ -n "$(conf_get keybox_url)" ] || [ -n "$(conf_get keybox_file)" ]; }; then
    bootlog "auto_keybox=1: the scheduled fetch loop is running every 15 minutes"
    nohup sh "$INTEGRITY_BIN/keybox-fetch.sh" loop >/dev/null 2>&1 &
fi

sh "$MODPATH/bin/fix-persist.sh" >/dev/null 2>&1

chmod 755 "$MODPATH/daemon" "$MODPATH/machikado" "$MODPATH/mazoku" 2>/dev/null
chmod 644 "$MODPATH/libtricky_store.so" "$MODPATH/service.apk" 2>/dev/null

ts_wanted=$(conf_get ts_daemon)
if [ "$ts_wanted" = 1 ] && [ -x "$MODPATH/daemon" ]; then
    bootlog "ts_daemon=1: starting the TrickyStore loop with a short-lived backoff"
    (
        cd "$MODPATH" || exit 1
        short=0
        while :; do
            started=$(date +%s)
            ./daemon
            finished=$(date +%s)
            if [ $((finished - started)) -lt 10 ]; then
                short=$((short + 1))
            else
                short=0
            fi
            if [ "$short" -ge 5 ]; then
                bootlog "ts_daemon: stopped after five short-lived runs under 10 s"
                break
            fi
            sleep 2
        done
    ) &
else
    bootlog "ts_daemon=$ts_wanted: the TrickyStore loop is not started"
fi

if [ -x "$MODPATH/bin/boot-verdict.sh" ]; then
    nohup sh "$MODPATH/bin/boot-verdict.sh" >/dev/null 2>&1 &
fi
