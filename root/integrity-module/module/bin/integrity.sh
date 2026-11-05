#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"
. "$INTEGRITY_BIN/keybox.sh"

status() {
    printf 'module: %s %s\n' "$(file_get "$MOD_DIR/module.prop" id)" "$(file_get "$MOD_DIR/module.prop" version)"
    printf 'tricky store payload: %s\n' "$([ -f "$MOD_DIR/service.apk" ] && echo present || echo missing)"
    printf 'pif companion: %s\n' "$([ -f "$MOD_DIR/zygisk/arm64-v8a.so" ] && echo present || echo missing)"
    printf 'targets: %s entries\n' "$(grep -cv '^#' "$TARGETS_FILE" 2>/dev/null | tr -d ' ')"
    printf 'security patch: %s\n' "$(file_get "$PIF_PROP" SECURITY_PATCH)"
    printf 'keybox_mode: %s\n' "$(conf_get keybox_mode)"
    printf 'auto_keybox: %s\n' "$(conf_get auto_keybox)"
    keybox_report
    printf 'last verdict in logcat: %s\n' "$(logcat -d -v brief 2>/dev/null | grep -o 'MEETS_[A-Z_]*' | tail -n 1)"
}

doctor() {
    rc=0
    printf '== module\n'
    if [ -f "$MOD_DIR/module.prop" ]; then
        printf '[ok] %s %s\n' "$(file_get "$MOD_DIR/module.prop" id)" "$(file_get "$MOD_DIR/module.prop" version)"
    else
        printf '[fail] %s is missing\n' "$MOD_DIR/module.prop"
        rc=1
    fi
    if [ -e "$MOD_DIR/disable" ]; then
        printf '[fail] the module is disabled\n'
        rc=1
    fi
    for f in classes.dex zygisk/arm64-v8a.so service.apk libtricky_store.so machikado daemon pif.prop; do
        if [ ! -e "$MOD_DIR/$f" ]; then
            printf '[fail] missing %s\n' "$f"
            rc=1
        fi
    done
    printf '== keystore daemon\n'
    if pgrep -f 'nice-name=TrickyStore' >/dev/null 2>&1; then
        printf '[ok] TrickyStore daemon is running\n'
    else
        printf '[fail] TrickyStore daemon is not running\n'
        rc=1
    fi
    printf '== zygisk\n'
    if [ -d "$INTEGRITY_ROOT/data/adb/modules/zygisksu" ] || [ -d "$INTEGRITY_ROOT/data/adb/modules/zygisk_next" ]; then
        printf '[ok] a zygisk provider module is installed\n'
    else
        printf '[fail] no zygisk provider: the PIF companion cannot load\n'
        rc=1
    fi
    printf '== keybox\n'
    keybox_report
    algs=$(keybox_algs)
    state=${algs%% *}
    rest=${algs#* }
    rsa=${rest##* }
    if [ "$state" = present ] && [ "$rsa" -eq 0 ]; then
        rc=1
    fi
    hits=$(logcat -d 2>/dev/null | grep -c 'Incomplete keybox')
    if [ "${hits:-0}" -gt 0 ]; then
        printf '[fail] Play logged "Incomplete keybox provided by overlays" %s times since boot\n' "$hits"
        rc=1
    fi
    printf '== security patch\n'
    if sp_out=$(sh "$INTEGRITY_BIN/sp.sh" check 2>&1); then
        printf '[ok] %s\n' "$(file_get "$PIF_PROP" SECURITY_PATCH)"
    else
        printf '%s\n' "$sp_out"
        rc=1
    fi
    printf '== target list\n'
    if tg_out=$(sh "$INTEGRITY_BIN/targets.sh" check 2>&1); then
        printf '[ok] Play Services, Play Store and the checker are in scope\n'
    else
        printf '%s\n' "$tg_out"
        rc=1
    fi
    printf '== rom prop hooks\n'
    if [ -n "$(getprop net.pixelos.version 2>/dev/null)" ]; then
        if [ "$(getprop persist.sys.pihooks.disable.gms_props 2>/dev/null)" = true ]; then
            printf '[ok] PixelOS prop imitation hooks are disabled for gms\n'
        else
            printf '[fail] PixelOS prop imitation hooks are active and fight the PIF props\n'
            rc=1
        fi
    else
        printf '[ok] no custom rom prop hook detected\n'
    fi
    printf '== verdict\n'
    last=$(logcat -d -v brief 2>/dev/null | grep -o 'MEETS_[A-Z_]*' | tail -n 1)
    printf '[info] last device verdict in logcat: %s\n' "${last:-none}"
    return $rc
}

verdict() {
    x=$(conf_get spic_tap_x)
    y=$(conf_get spic_tap_y)
    [ -n "$x" ] || x=360
    [ -n "$y" ] || y=594
    input keyevent KEYCODE_WAKEUP 2>/dev/null
    wm dismiss-keyguard 2>/dev/null
    sleep 1
    am force-stop "$CHECKER_PKG" 2>/dev/null
    logcat -c 2>/dev/null
    am start -n "$CHECKER_PKG/.MainActivity" >/dev/null 2>&1
    sleep 4
    input tap "$x" "$y" 2>/dev/null
    sleep 9
    logcat -d -v brief 2>/dev/null | grep -F 'System.out' | sed 's/^.*System.out( *[0-9]*): //'
}

case ${1:-status} in
    status) status ;;
    doctor) doctor ;;
    verdict) verdict ;;
    keybox) keybox_report ;;
    fix-adb) sh "$INTEGRITY_BIN/fix-persist.sh" && printf 'persistent properties checked\n' ;;
    keybox-mode)
        shift
        if [ -n "${1:-}" ]; then
            file_set "$CONF" keybox_mode "$1" && keybox_apply_mode
        else
            printf 'keybox_mode: %s\n' "$(conf_get keybox_mode)"
        fi
        ;;
    targets) shift; sh "$INTEGRITY_BIN/targets.sh" "$@" ;;
    sp) shift; sh "$INTEGRITY_BIN/sp.sh" "$@" ;;
    *)
        printf 'usage: integrity.sh status|doctor|verdict|keybox|keybox-mode <mode>|fix-adb|targets <cmd>|sp <cmd>\n' >&2
        exit 2
        ;;
esac
