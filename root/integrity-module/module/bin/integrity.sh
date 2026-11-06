#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"
. "$INTEGRITY_BIN/keybox.sh"

PKG=com.henrikherzig.playintegritychecker

status() {
    printf 'module: %s %s\n' "$(file_get "$MOD_DIR/module.prop" id)" "$(file_get "$MOD_DIR/module.prop" version)"
    printf 'tricky store payload: %s\n' "$([ -f "$MOD_DIR/service.apk" ] && echo present || echo missing)"
    printf 'pif companion: %s\n' "$([ -f "$MOD_DIR/zygisk/arm64-v8a.so" ] && echo present || echo missing)"
    printf 'targets: %s entries\n' "$(grep -cv '^#' "$TARGETS_FILE" 2>/dev/null | tr -d ' ')"
    printf 'security patch: %s\n' "$(file_get "$PIF_PROP" SECURITY_PATCH)"
    printf 'keybox_mode: %s, auto_keybox: %s, auto_verdict: %s, keep_adb: %s\n' \
        "$(conf_get keybox_mode)" "$(conf_get auto_keybox)" "$(conf_get auto_verdict)" "$(conf_get keep_adb)"
    keybox_report
    printf 'last verdict in logcat: %s\n' "$(logcat -d -v brief 2>/dev/null | grep -o 'MEETS_[A-Z_]*' | tail -n 1)"
}

launch_count() {
    logcat -d -v brief 2>/dev/null | grep -c 'tricky_store.MainKt'
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
    for f in classes.dex zygisk/arm64-v8a.so pif.prop teesim/daemon teesim/classes.dex teesim/arm64-v8a/libteesim_keymint.so teesim/arm64-v8a/inject; do
        if [ ! -e "$MOD_DIR/$f" ]; then
            printf '[fail] missing %s\n' "$f"
            rc=1
        fi
    done

    printf '== attestation provider\n'
    if [ -f "$MOD_DIR/teesim/daemon" ]; then
        printf '[ok] the TEESim payload is bundled at %s/teesim\n' "$MOD_DIR"
    else
        printf '[fail] the TEESim payload is missing under %s/teesim\n' "$MOD_DIR"
        rc=1
    fi
    ts_pid=$(pidof teesim 2>/dev/null | awk '{print $1}')
    if [ -n "$ts_pid" ]; then
        printf '[ok] teesim control daemon alive pid=%s\n' "$ts_pid"
    else
        printf '[fail] no teesim process: key attestation is not redirected\n'
        rc=1
    fi
    ks_pid=$(pidof keystore2 2>/dev/null | awk '{print $1}')
    if [ -n "$ks_pid" ]; then
        ks_maps=$(grep -c libteesim "/proc/$ks_pid/maps" 2>/dev/null | tr -d ' ')
        if [ "${ks_maps:-0}" -ge 1 ]; then
            printf '[ok] libteesim mapped %s time(s) inside keystore2 pid=%s\n' "$ks_maps" "$ks_pid"
        else
            printf '[fail] libteesim is not mapped inside keystore2, so nothing intercepts attestation\n'
            rc=1
        fi
    else
        printf '[fail] keystore2 is not running\n'
        rc=1
    fi
    if [ -f "$TEESIM_CONF" ]; then
        apps=$(sed -n '/"apps"/,/]/p' "$TEESIM_CONF" 2>/dev/null | grep -c '"')
        apps=$((apps - 1))
        printf '[info] teesim config: %s, profile apps: %s\n' "$TEESIM_CONF" "$apps"
    else
        printf '[fail] %s is missing; the interceptor has no profile\n' "$TEESIM_CONF"
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
        printf '[fail] keybox is incomplete: no rsa, so the provider cannot serve the rsa attestation record\n'
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
    for pkg in com.google.android.gms com.android.vending; do
        if grep -qxF "$pkg" "$TARGETS_FILE" 2>/dev/null; then
            printf '[ok] %s is in %s\n' "$pkg" "$TARGETS_FILE"
        else
            printf '[fail] %s is missing from %s\n' "$pkg" "$TARGETS_FILE"
            rc=1
        fi
    done
    if tg_out=$(sh "$INTEGRITY_BIN/targets.sh" check 2>&1); then
        printf '[ok] the required packages are in scope\n'
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

    printf '== hiding\n'
    susfs_version=$(command -v ksud >/dev/null 2>&1 && ksud susfs version 2>/dev/null)
    case "$susfs_version" in
        v*)
            printf '[ok] SUSFS %s is active\n' "$susfs_version"
            ;;
        *)
            printf '[fail] SUSFS is not active\n'
            rc=1
            ;;
    esac
    if [ -e /system/bin/su ]; then
        printf '[fail] /system/bin/su is visible in the default namespace\n'
        rc=1
    else
        printf '[ok] no /system/bin/su in the default namespace\n'
    fi
    pf=/data/property/persistent_properties
    pmode=$(stat -c '%a' "$pf" 2>/dev/null)
    if [ "$pmode" = 600 ]; then
        printf '[ok] persistent properties are 0600\n'
    else
        printf '[fail] %s is %s, init will drop every persistent property\n' "$pf" "$pmode"
        rc=1
    fi
    case "$(getprop persist.sys.usb.config 2>/dev/null)" in
        *adb*) printf '[ok] persist.sys.usb.config carries adb\n' ;;
        *) printf '[fail] persist.sys.usb.config lost adb\n'; rc=1 ;;
    esac

    printf '== verdict\n'
    last=$(logcat -d -v brief 2>/dev/null | grep -o 'MEETS_[A-Z_]*' | tail -n 1)
    printf '[info] last device verdict in logcat: %s\n' "${last:-none}"
    if [ -f "$TS_DIR/verdicts.jsonl" ]; then
        printf '[info] last raw verdict: %s\n' "$(tail -n 1 "$TS_DIR/verdicts.jsonl")"
    else
        printf '[info] no verdict recorded yet\n'
    fi
    return $rc
}

shown_focus() {
    dumpsys window 2>/dev/null | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^}]*\)}.*/\1/p' | head -n 1
}

verdict() {
    x=$(conf_get spic_tap_x)
    y=$(conf_get spic_tap_y)
    [ -n "$x" ] || x=360
    [ -n "$y" ] || y=594
    input keyevent KEYCODE_WAKEUP 2>/dev/null
    wm dismiss-keyguard 2>/dev/null
    sleep 1
    am force-stop "$PKG" 2>/dev/null
    am start -W -n "$PKG/.MainActivity" >/dev/null 2>&1
    focus=""
    for _ in $(seq 1 8); do
        focus=$(shown_focus)
        case $focus in
            *"$PKG"*) break ;;
        esac
        sleep 1
    done
    case $focus in
        *"$PKG"*) : ;;
        *)
            printf 'verdict skipped: the checker does not have focus (current: %s)\n' "${focus:-unknown}" >&2
            return 3
            ;;
    esac
    mark=$(date '+%m-%d %H:%M:%S.000')
    input tap "$x" "$y" 2>/dev/null
    sleep 9
    logcat -d -v brief -T "$mark" 2>/dev/null | grep -F 'System.out' | sed 's/^.*System.out( *[0-9]*): //'
}

case ${1:-status} in
    status) status ;;
    doctor) doctor ;;
    verdict) verdict ;;
    keybox) keybox_report ;;
    keybox-mode)
        shift
        if [ -n "${1:-}" ]; then
            file_set "$CONF" keybox_mode "$1" && keybox_apply_mode
        else
            printf 'keybox_mode: %s\n' "$(conf_get keybox_mode)"
        fi
        ;;
    fix-adb) sh "$INTEGRITY_BIN/fix-persist.sh" && printf 'persistent properties checked\n' ;;
    verdicts)
        shift
        n=${1:-3}
        if [ -f "$TS_DIR/verdicts.jsonl" ]; then
            tail -n "$n" "$TS_DIR/verdicts.jsonl"
        else
            printf 'no verdicts recorded yet\n'
        fi
        ;;
    targets) shift; sh "$INTEGRITY_BIN/targets.sh" "$@" ;;
    sp) shift; sh "$INTEGRITY_BIN/sp.sh" "$@" ;;
    *)
        printf 'usage: integrity.sh status|doctor|verdict|keybox|keybox-mode <mode>|fix-adb|verdicts [n]|targets <cmd>|sp <cmd>\n' >&2
        exit 2
        ;;
esac
