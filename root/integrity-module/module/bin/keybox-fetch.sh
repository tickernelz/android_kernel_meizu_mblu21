#!/system/bin/sh
bin=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin}"
. "$INTEGRITY_BIN/lib.sh"

STATE=$TS_DIR/keybox.state
PREV=$TS_DIR/keybox.prev.xml
SRC_STAMP=$TS_DIR/keybox.source
TICK=${KEYBOX_FETCH_TICK:-900}

state_get() {
    file_get "$STATE" "$1"
}

state_set() {
    key=$1
    value=$(printf '%s' "$2" | tr -d '\n')
    tmp_state=$STATE.tmp.$$
    if [ -f "$STATE" ]; then
        grep -v "^${key}=" "$STATE" > "$tmp_state" 2>/dev/null || : > "$tmp_state"
    else
        : > "$tmp_state"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp_state"
    mv "$tmp_state" "$STATE"
}

interval_hours() {
    h=$(conf_get keybox_fetch_interval_h)
    case $h in
        ''|*[!0-9]*) h=6 ;;
    esac
    [ "$h" -ge 1 ] || h=6
    [ "$h" -le 168 ] || h=168
    printf '%s' "$h"
}

requests_per_day() {
    h=$(interval_hours)
    n=$((24 / h))
    [ "$n" -ge 1 ] || n=1
    printf '%s' "$n"
}

seconds_until_due() {
    last=$(state_get last_attempt)
    case $last in
        ''|*[!0-9]*) printf '0'; return 0 ;;
    esac
    want=$(( $(interval_hours) * 3600 ))
    now=$(date +%s)
    left=$(( last + want - now ))
    [ "$left" -gt 0 ] || left=0
    printf '%s' "$left"
}

source_value() {
    u=$(conf_get keybox_url)
    if [ -n "$u" ]; then
        printf '%s' "$u"
        return 0
    fi
    f=$(conf_get keybox_file)
    [ -n "$f" ] && printf '%s' "$f"
}

is_due() {
    last=$(state_get last_attempt)
    [ -n "$last" ] || return 0
    now=$(date +%s)
    want=$(( $(interval_hours) * 3600 ))
    [ $(( now - last )) -ge "$want" ]
}

fetch_to() {
    src=$1
    dest=$2
    case $src in
        https://*)
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL --max-time 30 --proto '=https' --proto-redir '=https' -o "$dest" "$src"
            elif command -v wget >/dev/null 2>&1; then
                [ -n "$(conf_get keybox_sha256)" ] || return 5
                wget -q -O "$dest" --timeout=30 "$src"
            else
                return 4
            fi
            ;;
        file://*)
            p=${src#file://}
            [ -f "$p" ] || return 1
            cp -f "$p" "$dest"
            ;;
        /*)
            [ -f "$src" ] || return 1
            cp -f "$src" "$dest"
            ;;
        http://*)
            return 2
            ;;
        *)
            return 3
            ;;
    esac
}

restore_prev() {
    [ -f "$PREV" ] || return 1
    if ! out=$(sh "$INTEGRITY_BIN/keybox-validate.sh" --structural "$PREV" 2>/dev/null); then
        log_line "rollback unavailable: keybox.prev.xml is not usable ($out)"
        return 1
    fi
    cp -f "$PREV" "$KEYBOX"
    chmod 600 "$KEYBOX" 2>/dev/null
    log_line "rolled back to keybox.prev.xml ($out)"
}

run_heal() {
    [ "$(conf_get auto_keybox)" = 1 ] || return 0
    [ -n "$(source_value)" ] || return 0
    [ -f "$KEYBOX" ] || return 0
    self_heal
}

self_heal() {
    if out=$(sh "$INTEGRITY_BIN/keybox-validate.sh" --structural "$KEYBOX" 2>/dev/null); then
        return 0
    fi
    log_line "current keybox is not usable ($out)"
    restore_prev
}

attempt() {
    src=$1
    now=$(date +%s)
    state_set last_attempt "$now"
    state_set last_source "$src"
    mkdir -p "$TS_DIR" 2>/dev/null
    tmp=$TS_DIR/.keybox.incoming
    rm -f "$tmp"
    fetch_to "$src" "$tmp"
    rc=$?
    case $rc in
        2)
            rm -f "$tmp"
            state_set last_result refused-scheme
            log_line "keybox fetch refused: $src is plain http; https:// or file:// is required"
            return 0
            ;;
        3)
            rm -f "$tmp"
            state_set last_result refused-scheme
            log_line "keybox fetch refused: $src is neither https:// nor file://"
            return 0
            ;;
        4)
            rm -f "$tmp"
            state_set last_result no-fetcher
            log_line 'keybox fetch failed: neither curl nor wget is present'
            return 0
            ;;
        5)
            rm -f "$tmp"
            state_set last_result untrusted-fetcher
            log_line 'keybox fetch refused: this wget build does not validate TLS certificates, so keybox_sha256 is required'
            return 0
            ;;
        1)
            rm -f "$tmp"
            state_set last_result fetch-failed
            log_line "keybox fetch failed: cannot read $src"
            return 0
            ;;
        0) : ;;
        *)
            rm -f "$tmp"
            state_set last_result fetch-failed
            log_line "keybox fetch failed: $src returned an error"
            return 0
            ;;
    esac
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        state_set last_result empty
        log_line "keybox fetch rejected: $src produced an empty body"
        return 0
    fi
    want=$(conf_get keybox_sha256)
    got=$(sha256sum "$tmp" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$want" ] && [ "$want" != "$got" ]; then
        rm -f "$tmp"
        state_set last_result sha256-mismatch
        log_line "keybox fetch rejected: sha256 mismatch, want $want got $got"
        return 0
    fi
    if ! out=$(sh "$INTEGRITY_BIN/keybox-validate.sh" "$tmp" 2>/dev/null); then
        rm -f "$tmp"
        state_set last_result "rejected:$out"
        log_line "keybox fetch rejected: $out"
        self_heal
        return 0
    fi
    if [ "$(conf_get keybox_require_trusted)" = 1 ] && ! printf '%s' "$out" | grep -q 'chain=google'; then
        rm -f "$tmp"
        state_set last_result refused-untrusted-chain
        log_line "keybox fetch refused: $out (no Google or OEM root, so Play would not raise DEVICE)"
        return 0
    fi
    cur=$(sha256sum "$KEYBOX" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$cur" ] && [ "$cur" = "$got" ]; then
        rm -f "$tmp"
        state_set last_result unchanged
        state_set last_ok "$now"
        log_line "keybox unchanged, sha256 $got"
        return 0
    fi
    if [ -f "$KEYBOX" ]; then
        cp -f "$KEYBOX" "$PREV"
        log_line 'keybox backed up to keybox.prev.xml'
    fi
    if [ -f "$INTEGRITY_BIN/keybox.sh" ]; then
        if ! ( . "$INTEGRITY_BIN/keybox.sh"; keybox_install "$tmp" "fetched from $src" ); then
            rm -f "$tmp"
            state_set last_result install-failed
            return 0
        fi
    else
        mv "$tmp" "$KEYBOX"
        chmod 600 "$KEYBOX" 2>/dev/null
    fi
    rm -f "$tmp"
    printf 'source=%s\nts=%s\nsha256=%s\n' "$src" "$(date '+%Y-%m-%d %H:%M:%S')" "$got" > "$SRC_STAMP"
    chmod 600 "$SRC_STAMP" 2>/dev/null
    state_set last_result installed
    state_set last_ok "$now"
    state_set last_sha256 "$got"
    log_line "keybox installed from $src sha256=$got $out"
}

run() {
    [ "$(conf_get auto_keybox)" = 1 ] || return 0
    src=$(source_value)
    case $src in
        *' '*|*'"'*)
            log_line 'keybox fetch refused: the configured source contains a space or a quote'
            return 0
            ;;
    esac
    [ -n "$src" ] || return 0
    is_due || return 0
    attempt "$src"
}

status() {
    src=$(source_value)
    printf 'auto_keybox: %s\n' "$(conf_get auto_keybox)"
    printf 'source: %s\n' "${src:-none}"
    printf 'interval: %s h, requests per day: %s\n' "$(interval_hours)" "$(requests_per_day)"
    printf 'last_attempt: %s\n' "$(state_get last_attempt)"
    printf 'last_result: %s\n' "$(state_get last_result)"
    printf 'last_ok: %s\n' "$(state_get last_ok)"
    printf 'last_sha256: %s\n' "$(state_get last_sha256)"
    if [ -f "$SRC_STAMP" ]; then
        printf 'installed_from: %s\n' "$(file_get "$SRC_STAMP" source)"
        printf 'installed_at: %s\n' "$(file_get "$SRC_STAMP" ts)"
    fi
    printf 'current: %s\n' "$(sh "$INTEGRITY_BIN/keybox-validate.sh" "$KEYBOX" 2>/dev/null)"
    if [ -f "$PREV" ]; then
        printf 'previous: %s\n' "$(sh "$INTEGRITY_BIN/keybox-validate.sh" "$PREV" 2>/dev/null)"
    else
        printf 'previous: none\n'
    fi
}

loop() {
    while :; do
        run
        left=$(seconds_until_due)
        [ "$left" -gt 0 ] || left=$TICK
        [ "$left" -le 3600 ] || left=3600
        log_line "keybox fetch: next attempt in ${left}s (one request per $(interval_hours)h)"
        sleep "$left"
    done
}

case $1 in
    run) run ;;
    now) attempt "$(source_value)" ;;
    heal) run_heal ;;
    status) status ;;
    loop) loop ;;
    *)
        printf 'usage: %s run|now|heal|status|loop\n' "$0"
        exit 2
        ;;
esac
