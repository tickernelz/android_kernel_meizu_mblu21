#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"

targets_default() {
    printf '%s\n' com.android.vending com.google.android.gms com.google.android.gms.unstable com.google.android.gsf "$CHECKER_PKG"
}

targets_required() {
    printf '%s\n' com.android.vending com.google.android.gms com.google.android.gms.unstable
}

targets_apps_block() {
    first=1
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        pkg=$(printf '%s' "$line" | tr -d '\r' | sed 's/[!?]$//')
        [ -z "$pkg" ] && continue
        if [ "$first" = 1 ]; then
            printf '        "%s"' "$pkg"
            first=0
        else
            printf ',\n        "%s"' "$pkg"
        fi
    done < "$1"
    printf '\n'
}

targets_teesim_sync() {
    cfg=$TEESIM_CONF
    [ -f "$cfg" ] || return 0
    [ -f "$TARGETS_FILE" ] || return 0
    start=$(grep -n '"apps"' "$cfg" 2>/dev/null | head -n 1 | cut -d: -f1)
    [ -n "$start" ] || return 1
    end=$(tail -n +"$start" "$cfg" | grep -n '^[[:space:]]*\]' | head -n 1 | cut -d: -f1)
    [ -n "$end" ] || return 1
    end=$((start + end - 1))
    tmp=$cfg.apps.$$
    {
        head -n "$start" "$cfg"
        targets_apps_block "$TARGETS_FILE"
        tail -n +"$end" "$cfg"
    } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$cfg"
    printf 'teesim apps synced from %s (%s entries)\n' "$TARGETS_FILE" "$(grep -cv '^#' "$TARGETS_FILE" | tr -d ' ')"
}

targets_reset() {
    mkdir -p "$TS_DIR"
    targets_default > "$TARGETS_FILE"
    printf 'target list reset to %s packages\n' "$(targets_default | wc -l | tr -d ' ')"
}

targets_merge() {
    mkdir -p "$TS_DIR"
    [ -f "$TARGETS_FILE" ] || : > "$TARGETS_FILE"
    added=0
    for p in $(targets_default); do
        if grep -qxF "$p" "$TARGETS_FILE" 2>/dev/null; then
            continue
        fi
        printf '%s\n' "$p" >> "$TARGETS_FILE"
        added=$((added + 1))
    done
    printf 'target list: %s added, %s entries\n' "$added" "$(grep -cv '^#' "$TARGETS_FILE" | tr -d ' ')"
}

targets_add() {
    mkdir -p "$TS_DIR"
    [ -f "$TARGETS_FILE" ] || : > "$TARGETS_FILE"
    for p in "$@"; do
        if grep -qxF "$p" "$TARGETS_FILE" 2>/dev/null; then
            continue
        fi
        printf '%s\n' "$p" >> "$TARGETS_FILE"
    done
}

targets_rm() {
    [ -f "$TARGETS_FILE" ] || return 0
    for p in "$@"; do
        grep -vxF "$p" "$TARGETS_FILE" > "$TARGETS_FILE.tmp"
        mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
    done
}

targets_check() {
    rc=0
    for p in $(targets_required); do
        if ! grep -qxF "$p" "$TARGETS_FILE" 2>/dev/null; then
            printf 'WARN: %s missing from %s\n' "$p" "$TARGETS_FILE"
            rc=1
        fi
    done
    return $rc
}

case ${1:-list} in
    reset) targets_reset ;;
    merge) targets_merge; targets_teesim_sync ;;
    add) shift; targets_add "$@"; targets_teesim_sync ;;
    rm) shift; targets_rm "$@"; targets_teesim_sync ;;
    teesim) targets_teesim_sync ;;
    list) [ -f "$TARGETS_FILE" ] && cat "$TARGETS_FILE" ;;
    check) targets_check ;;
    *)
        printf 'usage: targets.sh reset|merge|add <pkg>...|rm <pkg>...|list|check\n' >&2
        exit 2
        ;;
esac
