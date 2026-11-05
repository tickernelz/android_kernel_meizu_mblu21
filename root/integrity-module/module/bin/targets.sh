#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"

targets_default() {
    printf '%s\n' com.android.vending com.google.android.gms com.google.android.gsf "$CHECKER_PKG"
}

targets_required() {
    printf '%s\n' com.android.vending com.google.android.gms
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
    merge) targets_merge ;;
    add) shift; targets_add "$@" ;;
    rm) shift; targets_rm "$@" ;;
    list) [ -f "$TARGETS_FILE" ] && cat "$TARGETS_FILE" ;;
    check) targets_check ;;
    *)
        printf 'usage: targets.sh reset|merge|add <pkg>...|rm <pkg>...|list|check\n' >&2
        exit 2
        ;;
esac
