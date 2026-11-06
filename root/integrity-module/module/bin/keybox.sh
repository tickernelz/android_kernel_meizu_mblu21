#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"

KEYBOX_LOG=$TS_DIR/keybox.log
KEYBOX_BACKUP_DIR=$TS_DIR/backup
TEESIM_DIR=$INTEGRITY_ROOT/data/adb/teesim
TEESIM_KEYBOX=$TEESIM_DIR/keybox.xml
TEESIM_MODULE=$INTEGRITY_ROOT/data/adb/modules/teesim

keylog() {
    mkdir -p "$TS_DIR" 2>/dev/null
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$KEYBOX_LOG" 2>/dev/null
}

keybox_algs() {
    if [ ! -f "$KEYBOX" ]; then
        printf 'none 0 0\n'
        return 0
    fi
    kb_ec=$(grep -c 'algorithm="ecdsa"' "$KEYBOX" 2>/dev/null)
    kb_rsa=$(grep -c 'algorithm="rsa"' "$KEYBOX" 2>/dev/null)
    printf 'present %s %s\n' "${kb_ec:-0}" "${kb_rsa:-0}"
}

keybox_sha256() {
    [ -f "$1" ] || return 1
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

keybox_validate() {
    kb_val_target=$1
    [ -n "$kb_val_target" ] || kb_val_target=$KEYBOX
    if [ -f "$INTEGRITY_BIN/keybox-validate.sh" ]; then
        sh "$INTEGRITY_BIN/keybox-validate.sh" "$kb_val_target" 2>/dev/null
        return $?
    fi
    [ -f "$kb_val_target" ] || { printf 'invalid missing\n'; return 1; }
    printf 'unchecked\n'
    return 0
}

keybox_current_state() {
    keybox_validate "$KEYBOX"
}

keybox_backup() {
    kb_bk_src=$1
    [ -f "$kb_bk_src" ] || return 0
    mkdir -p "$KEYBOX_BACKUP_DIR" 2>/dev/null || return 1
    kb_bk_dest=$KEYBOX_BACKUP_DIR/keybox-$(date +%Y%m%d%H%M%S).xml
    cp -f "$kb_bk_src" "$kb_bk_dest" 2>/dev/null || return 1
    chmod 600 "$kb_bk_dest" 2>/dev/null
    keylog "backup $(basename -- "$kb_bk_src") -> $kb_bk_dest sha256=$(keybox_sha256 "$kb_bk_dest")"
    printf '%s\n' "$kb_bk_dest"
}

keybox_teesim_present() {
    [ -d "$TEESIM_DIR" ] || [ -d "$TEESIM_MODULE" ]
}

keybox_sync_teesim() {
    keybox_teesim_present || return 0
    [ -f "$KEYBOX" ] || return 0
    mkdir -p "$TEESIM_DIR" 2>/dev/null
    if [ -f "$TEESIM_KEYBOX" ] && cmp -s "$KEYBOX" "$TEESIM_KEYBOX"; then
        return 0
    fi
    if [ -f "$TEESIM_KEYBOX" ]; then
        keybox_backup "$TEESIM_KEYBOX" >/dev/null
    fi
    cp -f "$KEYBOX" "$TEESIM_KEYBOX" 2>/dev/null || return 1
    chmod 600 "$TEESIM_KEYBOX" 2>/dev/null
    keylog "synced the active keybox to $TEESIM_KEYBOX for TEESimulator"
}

keybox_install() {
    kb_in_src=$1
    kb_in_why=$2
    [ -f "$kb_in_src" ] || { keylog "install refused: $kb_in_src is missing"; return 1; }
    if ! kb_in_out=$(keybox_validate "$kb_in_src"); then
        keylog "install refused: $kb_in_src $kb_in_out"
        return 1
    fi
    mkdir -p "$TS_DIR" 2>/dev/null
    if [ -f "$KEYBOX" ] && cmp -s "$kb_in_src" "$KEYBOX"; then
        keylog "kept the keybox already in place ($kb_in_why) sha256=$(keybox_sha256 "$KEYBOX")"
        keybox_sync_teesim
        return 0
    fi
    if [ -f "$KEYBOX" ]; then
        keybox_backup "$KEYBOX" >/dev/null
    fi
    kb_in_tmp=$KEYBOX.incoming.$$
    if ! cp -f "$kb_in_src" "$kb_in_tmp" 2>/dev/null; then
        rm -f "$kb_in_tmp"
        keylog "install failed: cannot stage $KEYBOX.incoming"
        return 1
    fi
    chmod 600 "$kb_in_tmp" 2>/dev/null
    if ! mv -f "$kb_in_tmp" "$KEYBOX" 2>/dev/null; then
        rm -f "$kb_in_tmp"
        keylog "install failed: cannot replace $KEYBOX"
        return 1
    fi
    keylog "installed $kb_in_src ($kb_in_why) sha256=$(keybox_sha256 "$KEYBOX") $kb_in_out"
    keybox_sync_teesim
    return 0
}

keybox_report() {
    kb_algs=$(keybox_algs)
    kb_state=${kb_algs%% *}
    kb_rest=${kb_algs#* }
    kb_ec=${kb_rest%% *}
    kb_rsa=${kb_rest##* }
    if [ "$kb_state" = none ]; then
        printf 'keybox: none\n'
        printf '  TrickyStore runs certificate-hack mode only: it rewrites the attestation the real TEE returns.\n'
    else
        if grep -q 'DeviceID="sw"' "$KEYBOX" 2>/dev/null; then
            printf 'keybox: %s bytes, ecdsa=%s rsa=%s, bundled software keybox (self-signed test chain)\n' "$(wc -c < "$KEYBOX" | tr -d ' ')" "$kb_ec" "$kb_rsa"
        else
            printf 'keybox: %s bytes, ecdsa=%s rsa=%s\n' "$(wc -c < "$KEYBOX" | tr -d ' ')" "$kb_ec" "$kb_rsa"
        fi
        printf '  sha256: %s\n' "$(keybox_sha256 "$KEYBOX")"
        printf '  validation: %s\n' "$(keybox_validate "$KEYBOX")"
        if [ "$kb_ec" -eq 0 ]; then
            printf '  incomplete: no ecdsa\n'
        fi
        if [ "$kb_rsa" -eq 0 ]; then
            printf '  incomplete: no rsa\n'
            printf '        The attestation chain needs one ecdsa and one rsa key; Play asks for each algorithm\n'
            printf '        separately, so an ecdsa-only file can never serve the rsa record.\n'
            printf '        The rsa private key cannot be derived from the ecdsa one; only a complete keybox fixes it.\n'
        fi
        if [ "$kb_ec" -gt 0 ] && [ "$kb_rsa" -gt 0 ]; then
            printf '  complete: both ecdsa and rsa keys are present\n'
        fi
    fi
    printf '  provider: %s\n' "$(keybox_provider)"
    if keybox_teesim_present; then
        if [ -f "$TEESIM_KEYBOX" ]; then
            printf '  teesim copy: %s sha256=%s\n' "$TEESIM_KEYBOX" "$(keybox_sha256 "$TEESIM_KEYBOX")"
        else
            printf '  teesim copy: none yet\n'
        fi
    fi
    if [ -f "$INTEGRITY_BIN/keybox-fetch.sh" ]; then
        kb_last=$(file_get "$TS_DIR/keybox.state" last_result)
        kb_stamp=$(file_get "$TS_DIR/keybox.state" last_attempt)
        kb_interval=$(conf_get keybox_fetch_interval_h)
        case $kb_interval in
            ''|*[!0-9]*) kb_interval=6 ;;
        esac
        [ "$kb_interval" -ge 1 ] || kb_interval=6
        kb_per_day=$((24 / kb_interval))
        [ "$kb_per_day" -ge 1 ] || kb_per_day=1
        printf '  fetch: %s (last attempt %s), every %sh = %s request(s)/day\n' "${kb_last:-never}" "${kb_stamp:-never}" "$kb_interval" "$kb_per_day"
    fi
    if [ -f "$TS_DIR/keybox.prev.xml" ]; then
        printf '  rollback copy: %s\n' "$(keybox_validate "$TS_DIR/keybox.prev.xml")"
    fi
    if [ -f "$KEYBOX_LOG" ]; then
        printf '  last keybox log: %s\n' "$(tail -n 1 "$KEYBOX_LOG")"
    fi
    return 0
}

keybox_provider() {
    if [ -d "$TEESIM_MODULE" ] && [ ! -f "$TEESIM_MODULE/disable" ]; then
        printf 'teesim (module present)\n'
        return 0
    fi
    if [ -f "$MOD_DIR/service.apk" ] && [ -f "$MOD_DIR/daemon" ]; then
        printf 'tricky (payload in this module)\n'
        return 0
    fi
    printf 'none\n'
}

keybox_auto_apply() {
    [ "$(conf_get auto_keybox)" = 1 ] || return 0
    if [ -f "$INTEGRITY_BIN/keybox-fetch.sh" ]; then
        sh "$INTEGRITY_BIN/keybox-fetch.sh" run
    fi
    return 0
}

keybox_apply_mode() {
    kb_mode=$(conf_get keybox_mode)
    : "${kb_mode:=auto}"
    case $kb_mode in
        existing|auto|software) : ;;
        *)
            keylog "WARN: unknown keybox_mode=$kb_mode, treating it as auto"
            kb_mode=auto
            ;;
    esac
    if [ "$kb_mode" = existing ]; then
        keylog 'keybox_mode=existing: the bundled software keybox is not installed'
        keybox_sync_teesim
        return 0
    fi
    if [ "$kb_mode" = auto ] && [ -f "$KEYBOX" ]; then
        keylog "keeping the keybox already at $KEYBOX sha256=$(keybox_sha256 "$KEYBOX")"
        keybox_sync_teesim
        return 0
    fi
    kb_src=$MOD_DIR/software-keybox.xml
    if [ ! -f "$kb_src" ]; then
        keylog "WARN: $kb_src is missing, keeping the current keybox"
        return 0
    fi
    keybox_install "$kb_src" 'bundled software keybox'
}
