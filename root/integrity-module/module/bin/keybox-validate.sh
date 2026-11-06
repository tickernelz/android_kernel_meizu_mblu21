#!/system/bin/sh
bin=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin}"

fail() {
    printf 'invalid %s\n' "$1"
    exit 1
}

structural=0
case $1 in
    -s|--structural)
        structural=1
        shift
        ;;
esac

f=$1
[ -n "$f" ] || fail missing
[ -f "$f" ] || fail missing

size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
[ -n "$size" ] || fail unreadable
[ "$size" -ge 512 ] 2>/dev/null || fail size
[ "$size" -le 65536 ] 2>/dev/null || fail size

LC_ALL=C tr -d '\000' < "$f" 2>/dev/null | cmp -s - "$f" 2>/dev/null || fail nul

grep -q '<!DOCTYPE' "$f" 2>/dev/null && fail doctype
grep -q '<!ENTITY' "$f" 2>/dev/null && fail doctype
grep -qi '<script' "$f" 2>/dev/null && fail script

root=$(grep -o '<[A-Za-z][A-Za-z0-9]*' "$f" 2>/dev/null | head -n 1 | tr -d '<')
[ "$root" = AndroidAttestation ] || fail root
grep -q '</AndroidAttestation>' "$f" 2>/dev/null || fail root-unclosed

scratch_root() {
    for cand in "${INTEGRITY_SCRATCH:-}" "$INTEGRITY_ROOT/data/adb/tricky_store" "${TMPDIR:-}" /data/local/tmp "$(dirname -- "$f")"; do
        [ -n "$cand" ] || continue
        mkdir -p "$cand" 2>/dev/null
        probe=$cand/.keybox-validate.probe.$$
        if mkdir "$probe" 2>/dev/null; then
            rmdir "$probe" 2>/dev/null
            printf '%s' "$cand"
            return 0
        fi
    done
    return 1
}

root=$(scratch_root) || fail scratch
tmp=$root/.keybox-validate.$$
rm -rf "$tmp"
mkdir -p "$tmp" 2>/dev/null || fail scratch
trap 'rm -rf "$tmp"' EXIT
trap 'rm -rf "$tmp"; exit 1' INT TERM HUP

if ! awk -v out="$tmp" -f "$INTEGRITY_BIN/keybox-split.awk" "$f" > "$tmp/split.txt" 2>/dev/null; then
    reason=$(sed -n 's/^error //p' "$tmp/split.txt" | head -n 1)
    rm -rf "$tmp"
    [ -n "$reason" ] || reason xml
    fail "$reason"
fi

names_of() {
    sed '1d;$d' "$1" 2>/dev/null | tr -d '\n' | base64 -d 2>/dev/null | od -An -v -tx1 | tr -d ' \n' | awk -f "$INTEGRITY_BIN/keybox-cert-names.awk" 2>/dev/null
}

ec=0
rsa=0
keys=0
certs=0

while IFS= read -r line; do
    case $line in
        'key '*) : ;;
        *) continue ;;
    esac
    idx=$(printf '%s\n' "$line" | sed -n 's/^key \([0-9]*\).*/\1/p')
    alg=$(printf '%s\n' "$line" | sed -n 's/.*alg=\([a-z]*\).*/\1/p')
    count=$(printf '%s\n' "$line" | sed -n 's/.*certs=\([0-9]*\).*/\1/p')
    case $alg in
        ecdsa) ec=$((ec + 1)) ;;
        rsa) rsa=$((rsa + 1)) ;;
    esac
    keys=$((keys + 1))
    certs=$((certs + count))
    i=1
    while [ "$i" -lt "$count" ]; do
        left=$(names_of "$tmp/cert-$idx-$i.pem" | sed -n 's/^issuer=//p')
        right=$(names_of "$tmp/cert-$idx-$((i + 1)).pem" | sed -n 's/^subject=//p')
        if [ -z "$left" ] || [ -z "$right" ] || [ "$left" != "$right" ]; then
            rm -rf "$tmp"
            fail "chain-link-$idx-$i"
        fi
        i=$((i + 1))
    done
    last=$(names_of "$tmp/cert-$idx-$count.pem")
    li=$(printf '%s\n' "$last" | sed -n 's/^issuer=//p')
    ls=$(printf '%s\n' "$last" | sed -n 's/^subject=//p')
    if [ -z "$li" ] || [ "$li" != "$ls" ]; then
        rm -rf "$tmp"
        fail "chain-root-$idx"
    fi
done < "$tmp/split.txt"

rm -rf "$tmp"

if [ "$structural" = 0 ]; then
    [ "$ec" -ge 1 ] || fail no-ecdsa
    [ "$rsa" -ge 1 ] || fail 'incomplete: no rsa'
fi

printf 'valid size=%s keys=%s certs=%s ec=%s rsa=%s\n' "$size" "$keys" "$certs" "$ec" "$rsa"
[ "$rsa" -ge 1 ] || printf 'incomplete: no rsa\n'
exit 0
