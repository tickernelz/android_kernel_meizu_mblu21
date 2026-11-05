#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"

keybox_algs() {
    if [ ! -f "$KEYBOX" ]; then
        printf 'none 0 0\n'
        return 0
    fi
    ec=$(grep -c 'algorithm="ecdsa"' "$KEYBOX" 2>/dev/null)
    rsa=$(grep -c 'algorithm="rsa"' "$KEYBOX" 2>/dev/null)
    printf 'present %s %s\n' "${ec:-0}" "${rsa:-0}"
}

keybox_validate() {
    target=$1
    [ -n "$target" ] || target=$KEYBOX
    if [ -f "$INTEGRITY_BIN/keybox-validate.sh" ]; then
        sh "$INTEGRITY_BIN/keybox-validate.sh" "$target" 2>/dev/null
        return $?
    fi
    [ -f "$target" ] || { printf 'invalid missing\n'; return 1; }
    printf 'unchecked\n'
    return 0
}

keybox_current_state() {
    state=$(keybox_validate "$KEYBOX")
    case $state in
        valid*) printf '%s\n' "$state" ;;
        *) printf '%s\n' "$state" ;;
    esac
}

keybox_report() {
    algs=$(keybox_algs)
    state=${algs%% *}
    rest=${algs#* }
    ec=${rest%% *}
    rsa=${rest##* }
    if [ "$state" = none ]; then
        printf 'keybox: none\n'
        printf '  TrickyStore runs certificate-hack mode only: it rewrites the attestation the real TEE returns.\n'
    else
        if grep -q 'DeviceID="sw"' "$KEYBOX" 2>/dev/null; then
            printf 'keybox: %s bytes, ecdsa=%s rsa=%s, bundled software keybox (self-signed test chain)\n' "$(wc -c < "$KEYBOX" | tr -d ' ')" "$ec" "$rsa"
        else
            printf 'keybox: %s bytes, ecdsa=%s rsa=%s\n' "$(wc -c < "$KEYBOX" | tr -d ' ')" "$ec" "$rsa"
        fi
        printf '  validation: %s\n' "$(keybox_validate "$KEYBOX")"
        if [ "$ec" -eq 0 ]; then
            printf '  WARN: no ecdsa key, and Play asks for an EC attestation record.\n'
        fi
        if [ "$rsa" -eq 0 ]; then
            printf '  WARN: no rsa key. Play logs "Incomplete keybox provided by overlays" and falls back to the\n'
            printf '        real TEE record, so the verdict stays at MEETS_BASIC_INTEGRITY.\n'
            printf '        The rsa private key cannot be derived from the ecdsa one; only a complete keybox fixes it.\n'
        fi
        if [ "$ec" -gt 0 ] && [ "$rsa" -gt 0 ]; then
            printf '  complete: both ecdsa and rsa keys are present\n'
        fi
    fi
    if [ -f "$INTEGRITY_BIN/keybox-fetch.sh" ]; then
        last=$(file_get "$TS_DIR/keybox.state" last_result)
        stamp=$(file_get "$TS_DIR/keybox.state" last_attempt)
        printf '  fetch: %s (last attempt %s)\n' "${last:-never}" "${stamp:-never}"
    fi
    if [ -f "$TS_DIR/keybox.prev.xml" ]; then
        printf '  rollback copy: %s\n' "$(keybox_validate "$TS_DIR/keybox.prev.xml")"
    fi
    return 0
}

keybox_auto_apply() {
    [ "$(conf_get auto_keybox)" = 1 ] || return 0
    if [ -f "$INTEGRITY_BIN/keybox-fetch.sh" ]; then
        sh "$INTEGRITY_BIN/keybox-fetch.sh" run
    fi
    return 0
}

keybox_apply_mode() {
    mode=$(conf_get keybox_mode)
    : "${mode:=auto}"
    case $mode in
        existing|auto|software) : ;;
        *)
            log_line "WARN: unknown keybox_mode=$mode, treating it as auto"
            mode=auto
            ;;
    esac
    if [ "$mode" = existing ]; then
        log_line 'keybox_mode=existing: the bundled software keybox is not installed'
        return 0
    fi
    if [ "$mode" = auto ] && [ -f "$KEYBOX" ]; then
        log_line "keeping the keybox already at $KEYBOX"
        return 0
    fi
    src=$MOD_DIR/software-keybox.xml
    if [ ! -f "$src" ]; then
        log_line "WARN: $src is missing, keeping the current keybox"
        return 0
    fi
    mkdir -p "$TS_DIR" 2>/dev/null
    if [ -f "$KEYBOX" ] && cmp -s "$src" "$KEYBOX"; then
        log_line 'the bundled software keybox is already in place'
        return 0
    fi
    if [ -f "$KEYBOX" ]; then
        cp -f "$KEYBOX" "$KEYBOX.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null
        log_line 'backed up the keybox that was in use'
    fi
    cp -f "$src" "$KEYBOX"
    chmod 600 "$KEYBOX" 2>/dev/null
    log_line 'installed the bundled software keybox (ecdsa+rsa)'
}
