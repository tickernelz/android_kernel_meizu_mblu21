#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mod=$here/../module
export INTEGRITY_BIN=$mod/bin
pass=0
fail=0

ok() { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

fresh() {
    T=$(mktemp -d)
    export INTEGRITY_ROOT=$T
    mkdir -p "$T/data/adb/tricky_store" "$T/data/adb/modules/playintegrityfix" "$T/bin"
    cp "$mod/integrity.conf" "$T/data/adb/tricky_store/integrity.conf"
    cp "$mod/target.txt" "$T/data/adb/tricky_store/target.txt"
    cp "$mod/security_patch.txt" "$T/data/adb/tricky_store/security_patch.txt"
    cp "$mod/pif.prop" "$T/data/adb/modules/playintegrityfix/pif.prop"
}

targets() { INTEGRITY_ROOT=$INTEGRITY_ROOT sh "$mod/bin/targets.sh" "$@"; }
sp() { INTEGRITY_ROOT=$INTEGRITY_ROOT sh "$mod/bin/sp.sh" "$@"; }

fresh
targets reset >/dev/null
n=$(wc -l < "$T/data/adb/tricky_store/target.txt")
[ "$n" -eq 4 ] && ok "targets reset writes 4 packages" || no "targets reset writes 4 packages (got $n)"
targets check >/dev/null && ok "default target list passes check" || no "default target list passes check"
targets rm com.google.android.gms >/dev/null
if targets check >/dev/null; then no "check fails when play services is missing"; else ok "check fails when play services is missing"; fi
targets add com.google.android.gms >/dev/null
targets add com.google.android.gms >/dev/null
c=$(grep -cxF com.google.android.gms "$T/data/adb/tricky_store/target.txt")
[ "$c" -eq 1 ] && ok "targets add is idempotent" || no "targets add is idempotent (got $c)"

fresh
printf 'auto_keybox=0\nkeybox_url=http://example.invalid/kb.xml\n' > "$T/data/adb/tricky_store/integrity.conf"
mkdir -p "$T/bin"
printf '#!/bin/sh\ntouch %s/curl-called\n' "$T" > "$T/bin/curl"
chmod 755 "$T/bin/curl"
( export PATH=$T/bin:$PATH; . "$mod/bin/keybox.sh"; keybox_auto_apply >/dev/null 2>&1 )
[ -e "$T/curl-called" ] && no "auto_keybox=0 never fetches" || ok "auto_keybox=0 never fetches"

printf 'auto_keybox=1\nkeybox_url=\n' > "$T/data/adb/tricky_store/integrity.conf"
( export PATH=$T/bin:$PATH; . "$mod/bin/keybox.sh"; keybox_auto_apply >/dev/null 2>&1 )
[ -e "$T/curl-called" ] && no "empty keybox_url never fetches" || ok "empty keybox_url never fetches"
grep -q 'keybox_url is empty' "$T/data/adb/tricky_store/integrity.log" && ok "empty keybox_url is logged" || no "empty keybox_url is logged"

fresh
printf 'auto_keybox=1\nkeybox_url=http://example.invalid/kb.xml\nkeybox_sha256=deadbeef\n' > "$T/data/adb/tricky_store/integrity.conf"
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do if [ "$1" = -o ]; then shift; printf "<xml/>" > "$1"; fi; shift; done\n' > "$T/bin/curl"
chmod 755 "$T/bin/curl"
( export PATH=$T/bin:$PATH; . "$mod/bin/keybox.sh"; keybox_auto_apply >/dev/null 2>&1 )
[ -e "$T/data/adb/tricky_store/keybox.xml" ] && no "sha256 mismatch keeps the old keybox" || ok "sha256 mismatch keeps the old keybox"
grep -q 'sha256 mismatch' "$T/data/adb/tricky_store/integrity.log" && ok "sha256 mismatch is logged" || no "sha256 mismatch is logged"
grep -q 'plain HTTP' "$T/data/adb/tricky_store/integrity.log" && ok "http source is called out" || no "http source is called out"

fresh
printf '<Key algorithm="ecdsa">\n' > "$T/data/adb/tricky_store/keybox.xml"
out=$(. "$mod/bin/keybox.sh"; keybox_report)
printf '%s' "$out" | grep -q 'no rsa key' && ok "ecdsa-only keybox is called incomplete" || no "ecdsa-only keybox is called incomplete"
rm -f "$T/data/adb/tricky_store/keybox.xml"
out=$(. "$mod/bin/keybox.sh"; keybox_report)
printf '%s' "$out" | grep -q 'certificate-hack mode' && ok "missing keybox reports certificate-hack mode" || no "missing keybox reports certificate-hack mode"
printf '<Key algorithm="ecdsa">\n<Key algorithm="rsa">\n' > "$T/data/adb/tricky_store/keybox.xml"
out=$(. "$mod/bin/keybox.sh"; keybox_report)
printf '%s' "$out" | grep -q 'complete' && ok "ecdsa+rsa keybox is complete" || no "ecdsa+rsa keybox is complete"

[ "$(sp next5 260918)" = 2026-10-05 ] && ok "next5 260918 -> 2026-10-05" || no "next5 260918 -> 2026-10-05"
[ "$(sp next5 261231)" = 2027-01-05 ] && ok "next5 261231 rolls into 2027" || no "next5 261231 rolls into 2027"

fresh
sp check >/dev/null && ok "shipped security patch matches the fingerprint build id" || no "shipped security patch matches the fingerprint build id"
sed -i 's|^FINGERPRINT=.*|FINGERPRINT=google/bluejay_beta/bluejay:CANARY/ZP11.260918.007/16484274:user/release-keys|' "$T/data/adb/modules/playintegrityfix/pif.prop"
sp set 2026-10-05 >/dev/null
grep -qx 'system=2026-10-05' "$T/data/adb/tricky_store/security_patch.txt" && ok "sp set rewrites security_patch.txt" || no "sp set rewrites security_patch.txt"
grep -qx 'SECURITY_PATCH=2026-10-05' "$T/data/adb/modules/playintegrityfix/pif.prop" && ok "sp set rewrites pif.prop" || no "sp set rewrites pif.prop"
sp check >/dev/null && ok "sp check accepts the aligned pair" || no "sp check accepts the aligned pair"
sp set 2026-06-05 >/dev/null
if sp check >/dev/null; then no "sp check rejects a rom-aligned date"; else ok "sp check rejects a rom-aligned date"; fi

fresh
printf 'system=2026-11-05\nvendor=2024-12-05\nboot=2026-11-05\n' > "$T/data/adb/tricky_store/security_patch.txt"
if out=$(sp check 2>&1); then no "sp check catches a divergent vendor line"; else ok "sp check catches a divergent vendor line"; fi
printf '%s' "$out" | grep -q 'vendor=' && ok "divergent vendor line is named" || no "divergent vendor line is named"

fresh
mkdir -p "$T/data/property"
printf 'x' > "$T/data/property/persistent_properties"
chmod 0666 "$T/data/property/persistent_properties"
sh "$mod/post-fs-data.sh"
[ "$(stat -c %a "$T/data/property/persistent_properties")" = 600 ] && ok "post-fs-data restores persistent_properties to 0600" || no "post-fs-data restores persistent_properties to 0600"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
