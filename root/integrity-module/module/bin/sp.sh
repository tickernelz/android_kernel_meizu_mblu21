#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"

ym_next5() {
    yy=20$(printf '%s' "$1" | cut -c1-2)
    mm=$(printf '%s' "$1" | cut -c3-4 | sed 's/^0*//')
    mm=${mm:-0}
    if [ "$mm" -eq 12 ]; then
        yy=$((yy + 1))
        mm=1
    else
        mm=$((mm + 1))
    fi
    printf '%04d-%02d-05\n' "$yy" "$mm"
}

sp_show() {
    printf 'security_patch.txt:\n'
    if [ -f "$SP_FILE" ]; then
        sed 's/^/  /' "$SP_FILE"
    else
        printf '  (missing)\n'
    fi
    printf 'pif.prop SECURITY_PATCH: %s\n' "$(file_get "$PIF_PROP" SECURITY_PATCH)"
}

sp_set() {
    case ${1:-} in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
        *)
            printf 'usage: integrity.sh sp set YYYY-MM-DD\n' >&2
            return 2
            ;;
    esac
    mkdir -p "$TS_DIR"
    printf 'system=%s\nvendor=%s\nboot=%s\n' "$1" "$1" "$1" > "$SP_FILE"
    file_set "$PIF_PROP" SECURITY_PATCH "$1" || {
        printf 'WARN: cannot update %s\n' "$PIF_PROP" >&2
        return 1
    }
    printf 'security patch set to %s in %s and %s\n' "$1" "$SP_FILE" "$PIF_PROP"
}

sp_check() {
    rc=0
    sp=$(file_get "$PIF_PROP" SECURITY_PATCH)
    if [ -z "$sp" ]; then
        printf 'WARN: %s has no SECURITY_PATCH\n' "$PIF_PROP"
        return 1
    fi
    for k in system vendor boot; do
        v=$(sed -n "s/^$k=//p" "$SP_FILE" 2>/dev/null | tail -n 1)
        if [ -z "$v" ]; then
            printf 'WARN: %s has no %s= line\n' "$SP_FILE" "$k"
            rc=1
            continue
        fi
        if [ "$v" != "$sp" ] && [ "$(printf '%s' "$v" | tr -d '-')" != "$(printf '%s' "$sp" | tr -d '-')" ]; then
            printf 'WARN: %s=%s but pif.prop SECURITY_PATCH=%s\n' "$k" "$v" "$sp"
            rc=1
        fi
    done
    case $sp in
        *-05) : ;;
        *)
            printf 'WARN: SECURITY_PATCH %s does not sit on the 5th\n' "$sp"
            rc=1
            ;;
    esac
    fp=$(file_get "$PIF_PROP" FINGERPRINT)
    build=$(printf '%s' "$fp" | awk -F/ '{print $4}')
    stamp=$(printf '%s' "$build" | grep -oE '[0-9]{6}' | head -n 1)
    if [ -n "$stamp" ]; then
        want=$(ym_next5 "$stamp")
        if [ "$want" != "$sp" ]; then
            printf 'WARN: fingerprint build id %s implies %s, pif.prop says %s\n' "$build" "$want" "$sp"
            rc=1
        fi
    else
        printf 'WARN: cannot read a YYMMDD stamp from build id %s\n' "$build"
        rc=1
    fi
    return $rc
}

case ${1:-show} in
    show) sp_show ;;
    set) shift; sp_set "$@" ;;
    check) sp_check ;;
    next5) shift; ym_next5 "$@" ;;
    *)
        printf 'usage: sp.sh show|set <YYYY-MM-DD>|check|next5 <YYMMDD>\n' >&2
        exit 2
        ;;
esac
