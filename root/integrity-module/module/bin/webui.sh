#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"
. "$INTEGRITY_BIN/keybox.sh"

status() {
    printf 'provider_pid=%s\n' "$(pidof teesim 2>/dev/null | awk '{print $1}')"
    ks=$(pidof keystore2 2>/dev/null | awk '{print $1}')
    printf 'keystore_pid=%s\n' "$ks"
    printf 'keystore_maps=%s\n' "$(grep -c libteesim "/proc/$ks/maps" 2>/dev/null | tr -d ' ')"
    algs=$(keybox_algs)
    printf 'keybox_state=%s\n' "${algs%% *}"
    rest=${algs#* }
    printf 'keybox_ecdsa=%s\n' "${rest%% *}"
    printf 'keybox_rsa=%s\n' "${rest##* }"
    printf 'keybox_sha256=%s\n' "$(keybox_sha256 "$KEYBOX")"
    printf 'keybox_bytes=%s\n' "$([ -f "$KEYBOX" ] && wc -c < "$KEYBOX" | tr -d ' ')"
    val=$(keybox_validate "$KEYBOX" 2>/dev/null)
    printf 'keybox_validation=%s\n' "$val"
    printf 'keybox_chain=%s\n' "$(printf '%s' "$val" | sed -n 's/.*chain=\([a-z]*\).*/\1/p')"
    printf 'keybox_mtime=%s\n' "$([ -f "$KEYBOX" ] && date -r "$KEYBOX" '+%Y-%m-%d %H:%M' 2>/dev/null)"
    printf 'keybox_source=%s\n' "$(file_get "$TS_DIR/keybox.state" last_source)"
    printf 'fetch_interval_h=%s\n' "$(conf_get keybox_fetch_interval_h)"
    printf 'fetch_auto=%s\n' "$(conf_get auto_keybox)"
    printf 'fetch_last=%s\n' "$(file_get "$TS_DIR/keybox.state" last_result)"
    printf 'apps=%s\n' "$(sed -n '/"apps"/,/]/p' "$TEESIM_CONF" 2>/dev/null | grep -c '"' | tr -d ' ')"
    if [ -f "$TS_DIR/verdicts.jsonl" ]; then
        last=$(tail -n 1 "$TS_DIR/verdicts.jsonl")
        printf 'verdict_device=%s\n' "$(printf '%s' "$last" | sed -n 's/.*"device":"\([^"]*\)".*/\1/p')"
        printf 'verdict_app=%s\n' "$(printf '%s' "$last" | sed -n 's/.*"app":"\([^"]*\)".*/\1/p')"
        printf 'verdict_licensing=%s\n' "$(printf '%s' "$last" | sed -n 's/.*"licensing":"\([^"]*\)".*/\1/p')"
        printf 'verdict_ts=%s\n' "$(printf '%s' "$last" | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p')"
    fi
    printf 'last_keylog=%s\n' "$(tail -n 1 "$KEYBOX_LOG" 2>/dev/null)"
}

case ${1:-status} in
    status) status ;;
    refresh)
        sh "$INTEGRITY_BIN/keybox-fetch.sh" now 2>&1
        status ;;
    verdict)
        sh "$INTEGRITY_BIN/integrity.sh" verdict 2>&1
        ;;
    *)
        printf 'usage: %s status|refresh|verdict\n' "$0" >&2
        exit 2
        ;;
esac
