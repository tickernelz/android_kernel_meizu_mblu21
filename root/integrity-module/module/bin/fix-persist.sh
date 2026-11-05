#!/system/bin/sh
ROOT=${INTEGRITY_ROOT:-}
PF=$ROOT/data/property/persistent_properties
LOGDIR=$ROOT/data/adb/tricky_store
BIN=$(dirname -- "$0")

if [ -f "$BIN/lib.sh" ]; then
    . "$BIN/lib.sh"
fi

log() {
    mkdir -p "$LOGDIR" 2>/dev/null
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOGDIR/integrity.log" 2>/dev/null
    printf '%s\n' "$*"
}

if [ -f "$PF" ]; then
    mode=$(stat -c '%a' "$PF" 2>/dev/null)
    if [ "$mode" != 600 ]; then
        chown root:root "$PF" 2>/dev/null
        chmod 600 "$PF" 2>/dev/null
        log "repaired $PF mode $mode -> 600 so init accepts it on the next boot"
    fi
fi

if command -v getprop >/dev/null 2>&1; then
    keep=$(conf_get keep_adb)
    [ -n "$keep" ] || keep=1
    if [ "$keep" = 1 ]; then
        case "$(getprop persist.sys.usb.config)" in
            *adb*) : ;;
            *)
                setprop persist.sys.usb.config adb 2>/dev/null
                log "re-armed persist.sys.usb.config=adb (keep_adb=1)"
                ;;
        esac
    fi
fi
