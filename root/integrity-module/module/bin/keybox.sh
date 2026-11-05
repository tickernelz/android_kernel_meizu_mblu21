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

keybox_report() {
    algs=$(keybox_algs)
    state=${algs%% *}
    rest=${algs#* }
    ec=${rest%% *}
    rsa=${rest##* }
    if [ "$state" = none ]; then
        printf 'keybox: none\n'
        printf '  TrickyStore runs certificate-hack mode only: it rewrites the attestation the real TEE returns.\n'
        return 0
    fi
    if grep -q 'DeviceID="sw"' "$KEYBOX" 2>/dev/null; then
        printf 'keybox: %s bytes, ecdsa=%s rsa=%s, bundled software keybox (self-signed test chain)\n' "$(wc -c < "$KEYBOX" | tr -d ' ')" "$ec" "$rsa"
    else
        printf 'keybox: %s bytes, ecdsa=%s rsa=%s\n' "$(wc -c < "$KEYBOX" | tr -d ' ')" "$ec" "$rsa"
    fi
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
    return 0
}

keybox_auto_apply() {
    [ "$(conf_get auto_keybox)" = 1 ] || return 0
    url=$(conf_get keybox_url)
    if [ -z "$url" ]; then
        log_line 'auto_keybox=1 but keybox_url is empty: nothing fetched'
        return 0
    fi
    case $url in
        https://*) : ;;
        http://*) log_line "WARN: $url uses plain HTTP, so nothing on the path is authenticated" ;;
        *) log_line "WARN: $url is not an http(s) URL, refused"; return 0 ;;
    esac
    case $url in
        *' '*|*'"'*) log_line 'WARN: keybox_url contains a space or a quote, refused'; return 0 ;;
    esac
    want=$(conf_get keybox_sha256)
    if [ -z "$want" ]; then
        log_line 'WARN: no keybox_sha256 configured, so the served file is trusted as it arrives'
    fi
    if command -v curl >/dev/null 2>&1; then
        fetch() { curl -fsSL --max-time 30 -o "$1" "$2"; }
    elif command -v wget >/dev/null 2>&1; then
        fetch() { wget -q -O "$1" --timeout=30 "$2"; }
    else
        log_line 'WARN: neither curl nor wget is present: nothing fetched'
        return 0
    fi
    mkdir -p "$TS_DIR" 2>/dev/null
    tmp=$TS_DIR/.keybox.download
    if ! fetch "$tmp" "$url" 2>/dev/null; then
        log_line "fetch failed: $url"
        rm -f "$tmp" 2>/dev/null
        return 0
    fi
    got=$(sha256sum "$tmp" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$want" ] && [ "$want" != "$got" ]; then
        log_line "sha256 mismatch: want $want got $got, keeping the current keybox"
        rm -f "$tmp" 2>/dev/null
        return 0
    fi
    if [ -f "$KEYBOX" ] && [ "$(sha256sum "$KEYBOX" 2>/dev/null | cut -d' ' -f1)" = "$got" ]; then
        log_line "keybox unchanged, sha256 $got"
        rm -f "$tmp" 2>/dev/null
        return 0
    fi
    mv "$tmp" "$KEYBOX"
    chmod 600 "$KEYBOX" 2>/dev/null
    log_line "keybox replaced from $url sha256=$got"
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
    if [ -f "$KEYBOX" ]; then
        cp -f "$KEYBOX" "$KEYBOX.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null
        log_line "backed up the keybox that was in use"
    fi
    cp -f "$src" "$KEYBOX"
    chmod 600 "$KEYBOX" 2>/dev/null
    log_line "installed the bundled software keybox (ecdsa+rsa)"
}
