#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mod=$here/../module
export INTEGRITY_BIN=$mod/bin
pass=0
fail=0
FX=$(mktemp -d)

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
mkdir -p "$T/bin" "$FX"
printf '#!/bin/sh\ntouch %s/curl-called\n' "$T" > "$T/bin/curl"
chmod 755 "$T/bin/curl"
printf 'auto_keybox=0\nkeybox_url=http://example.invalid/kb.xml\n' > "$T/data/adb/tricky_store/integrity.conf"
( export PATH=$T/bin:$PATH; . "$mod/bin/keybox.sh"; keybox_auto_apply >/dev/null 2>&1 )
[ -e "$T/curl-called" ] && no "auto_keybox=0 never fetches" || ok "auto_keybox=0 never fetches"

rm -f "$T/curl-called"
printf 'auto_keybox=1\n' > "$T/data/adb/tricky_store/integrity.conf"
( export PATH=$T/bin:$PATH; . "$mod/bin/keybox.sh"; keybox_auto_apply >/dev/null 2>&1 )
[ -e "$T/curl-called" ] && no "no configured source never fetches" || ok "no configured source never fetches"

mkec() {
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$FX/$1-ca.key" -out "$FX/$1-ca.pem" -subj "/CN=$3" -days 30 >/dev/null 2>&1
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$FX/$1-leaf.key" -out "$FX/$1-leaf.csr" -subj "/CN=$2" >/dev/null 2>&1
    openssl x509 -req -in "$FX/$1-leaf.csr" -CA "$FX/$1-ca.pem" -CAkey "$FX/$1-ca.key" -CAcreateserial -out "$FX/$1-leaf.pem" -days 30 >/dev/null 2>&1
}

mkrsa() {
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$FX/$1-ca.key" -out "$FX/$1-ca.pem" -subj "/CN=$3" -days 30 >/dev/null 2>&1
    openssl req -new -newkey rsa:2048 -nodes -keyout "$FX/$1-leaf.key" -out "$FX/$1-leaf.csr" -subj "/CN=$2" >/dev/null 2>&1
    openssl x509 -req -in "$FX/$1-leaf.csr" -CA "$FX/$1-ca.pem" -CAkey "$FX/$1-ca.key" -CAcreateserial -out "$FX/$1-leaf.pem" -days 30 >/dev/null 2>&1
}

emit_key() {
    printf '    <Key algorithm="%s">\n      <PrivateKey format="pem">\n' "$1"
    sed 's/^/        /' "$2"
    printf '      </PrivateKey>\n      <CertificateChain>\n        <NumberOfCertificates>2</NumberOfCertificates>\n        <Certificate format="pem">\n'
    sed 's/^/          /' "$3"
    printf '        </Certificate>\n        <Certificate format="pem">\n'
    sed 's/^/          /' "$4"
    printf '        </Certificate>\n      </CertificateChain>\n    </Key>\n'
}

open_box() {
    printf '<?xml version="1.0"?>\n<AndroidAttestation>\n    <NumberOfKeyboxes>1</NumberOfKeyboxes>\n    <Keybox DeviceID="%s">\n' "$1"
}

close_box() {
    printf '    </Keybox>\n</AndroidAttestation>\n'
}

mkec ecleaf "Test EC Leaf" "Test EC CA"
mkec ecother "Test Other Leaf" "Test Other CA"
mkrsa rsaleaf "Test RSA Leaf" "Test RSA CA"

{
    open_box sw
    emit_key ecdsa "$FX/ecleaf-leaf.key" "$FX/ecleaf-leaf.pem" "$FX/ecleaf-ca.pem"
    emit_key rsa "$FX/rsaleaf-leaf.key" "$FX/rsaleaf-leaf.pem" "$FX/rsaleaf-ca.pem"
    close_box
} > "$FX/valid.xml"

{
    open_box sw2
    emit_key ecdsa "$FX/ecleaf-leaf.key" "$FX/ecleaf-leaf.pem" "$FX/ecleaf-ca.pem"
    emit_key rsa "$FX/rsaleaf-leaf.key" "$FX/rsaleaf-leaf.pem" "$FX/rsaleaf-ca.pem"
    close_box
} > "$FX/valid2.xml"

{
    open_box sw
    emit_key ecdsa "$FX/ecleaf-leaf.key" "$FX/ecleaf-leaf.pem" "$FX/ecleaf-ca.pem"
    close_box
} > "$FX/ec-only.xml"

{
    open_box sw
    emit_key ecdsa "$FX/ecleaf-leaf.key" "$FX/ecleaf-leaf.pem" "$FX/ecother-ca.pem"
    emit_key rsa "$FX/rsaleaf-leaf.key" "$FX/rsaleaf-leaf.pem" "$FX/rsaleaf-ca.pem"
    close_box
} > "$FX/broken-chain.xml"

{
    printf '<?xml version="1.0"?>\n<!DOCTYPE foo [<!ENTITY x "y">]>\n<AndroidAttestation>\n    <Keybox DeviceID="sw">\n'
    printf '%*s\n' 600 ''
    printf '    </Keybox>\n</AndroidAttestation>\n'
} > "$FX/doctype.xml"

{
    printf '<?xml version="1.0"?>\n<AndroidAttestation>\n'
    printf '%*s\n' 600 ''
    printf '</AndroidAttestation>\n'
} > "$FX/no-key.xml"

validate() { sh "$mod/bin/keybox-validate.sh" "$1" 2>&1; }

out=$(validate "$FX/valid.xml") && ok "validator accepts an ecdsa+rsa box with linked chains" || no "validator accepts an ecdsa+rsa box with linked chains ($out)"
printf '%s' "$out" | grep -q 'ec=1 rsa=1' && ok "validator counts one key per algorithm" || no "validator counts one key per algorithm ($out)"

if out=$(validate "$FX/ec-only.xml"); then no "validator rejects an ecdsa-only box"; else ok "validator rejects an ecdsa-only box"; fi
printf '%s' "$out" | grep -q 'invalid no-rsa' && ok "ecdsa-only rejection names the missing rsa key" || no "ecdsa-only rejection names the missing rsa key ($out)"

if out=$(validate "$FX/broken-chain.xml"); then no "validator rejects a certificate chain that does not link"; else ok "validator rejects a certificate chain that does not link"; fi
printf '%s' "$out" | grep -q 'invalid chain-link-1-1' && ok "broken chain is reported per key and hop" || no "broken chain is reported per key and hop ($out)"

if out=$(validate "$FX/doctype.xml"); then no "validator rejects a DOCTYPE"; else ok "validator rejects a DOCTYPE"; fi
printf '%s' "$out" | grep -q 'invalid doctype' && ok "doctype rejection has its own reason" || no "doctype rejection has its own reason ($out)"

if out=$(validate "$FX/no-key.xml"); then no "validator rejects a box without keys"; else ok "validator rejects a box without keys"; fi
printf '%s' "$out" | grep -q 'invalid no-key' && ok "keyless box rejection has its own reason" || no "keyless box rejection has its own reason ($out)"

if out=$(sh "$mod/bin/keybox-validate.sh" --structural "$FX/ec-only.xml"); then ok "structural mode accepts an incomplete owner keybox"; else no "structural mode accepts an incomplete owner keybox ($out)"; fi
if out=$(validate "$FX/ec-only.xml"); then no "strict mode still rejects the same file"; else ok "strict mode still rejects the same file"; fi

fetch() { INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" "$@"; }

fresh
cp "$FX/valid.xml" "$T/data/adb/tricky_store/keybox.xml"
printf 'auto_keybox=1\nkeybox_url=file://%s/valid2.xml\nkeybox_fetch_interval_h=24\n' "$FX" > "$T/data/adb/tricky_store/integrity.conf"
fetch run >/dev/null 2>&1
cmp -s "$FX/valid2.xml" "$T/data/adb/tricky_store/keybox.xml" && ok "file:// fetch installs a validated keybox" || no "file:// fetch installs a validated keybox"
cmp -s "$FX/valid.xml" "$T/data/adb/tricky_store/keybox.prev.xml" && ok "the replaced keybox is kept as keybox.prev.xml" || no "the replaced keybox is kept as keybox.prev.xml"
grep -q 'keybox installed from file://' "$T/data/adb/tricky_store/integrity.log" && ok "an install writes one log line" || no "an install writes one log line"
grep -q 'BEGIN CERTIFICATE' "$T/data/adb/tricky_store/integrity.log" && no "the log never carries keybox content" || ok "the log never carries keybox content"

before=$(sha256sum "$T/data/adb/tricky_store/keybox.xml" | cut -d' ' -f1)
fetch run >/dev/null 2>&1
after=$(sha256sum "$T/data/adb/tricky_store/keybox.xml" | cut -d' ' -f1)
[ "$before" = "$after" ] && ok "a second run inside the interval does not touch the keybox" || no "a second run inside the interval does not touch the keybox"

printf 'auto_keybox=1\nkeybox_url=http://example.invalid/kb.xml\n' > "$T/data/adb/tricky_store/integrity.conf"
fetch now >/dev/null 2>&1
cmp -s "$FX/valid2.xml" "$T/data/adb/tricky_store/keybox.xml" && ok "a plain http source is refused and the keybox survives" || no "a plain http source is refused and the keybox survives"
grep -q 'is plain http' "$T/data/adb/tricky_store/integrity.log" && ok "the http refusal is logged with the reason" || no "the http refusal is logged with the reason"

printf 'auto_keybox=1\nkeybox_url=file://%s/ec-only.xml\n' "$FX" > "$T/data/adb/tricky_store/integrity.conf"
fetch now >/dev/null 2>&1
cmp -s "$FX/valid2.xml" "$T/data/adb/tricky_store/keybox.xml" && ok "a keybox that fails validation never replaces the working one" || no "a keybox that fails validation never replaces the working one"
grep -q 'keybox fetch rejected: invalid no-rsa' "$T/data/adb/tricky_store/integrity.log" && ok "the validation failure is logged with its reason" || no "the validation failure is logged with its reason"

printf 'auto_keybox=1\nkeybox_url=file://%s/broken-chain.xml\n' "$FX" > "$T/data/adb/tricky_store/integrity.conf"
fetch now >/dev/null 2>&1
cmp -s "$FX/valid2.xml" "$T/data/adb/tricky_store/keybox.xml" && ok "a broken chain never replaces the working keybox" || no "a broken chain never replaces the working keybox"

printf 'auto_keybox=1\nkeybox_url=file://%s/valid.xml\nkeybox_sha256=deadbeef\n' "$FX" > "$T/data/adb/tricky_store/integrity.conf"
fetch now >/dev/null 2>&1
cmp -s "$FX/valid2.xml" "$T/data/adb/tricky_store/keybox.xml" && ok "a sha256 pin mismatch keeps the working keybox" || no "a sha256 pin mismatch keeps the working keybox"
grep -q 'sha256 mismatch' "$T/data/adb/tricky_store/integrity.log" && ok "the pin mismatch is logged" || no "the pin mismatch is logged"

printf 'garbage' > "$T/data/adb/tricky_store/keybox.xml"
fetch heal >/dev/null 2>&1
cmp -s "$FX/valid.xml" "$T/data/adb/tricky_store/keybox.prev.xml" && ok "heal brings back the keybox from keybox.prev.xml" || no "heal brings back the keybox from keybox.prev.xml"
sh "$mod/bin/keybox-validate.sh" "$T/data/adb/tricky_store/keybox.xml" >/dev/null 2>&1 && ok "the healed keybox validates" || no "the healed keybox validates"
fetch status >/dev/null 2>&1 && ok "status prints without a configured source" || no "status prints without a configured source"

fresh
url_a='file:///tmp/a|b&c\\d/kb-a.xml'
url_b='file:///tmp/e|f&g\\h/kb-b.xml'
printf 'auto_keybox=1\nkeybox_url=%s\n' "$url_a" > "$T/data/adb/tricky_store/integrity.conf"
err_a=$(INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" now 2>&1 >/dev/null)
first=$(sed -n 's/^last_attempt=//p' "$T/data/adb/tricky_store/keybox.state" | tail -n 1)
printf 'auto_keybox=1\nkeybox_url=%s\n' "$url_b" > "$T/data/adb/tricky_store/integrity.conf"
sleep 1
err_b=$(INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" now 2>&1 >/dev/null)
second=$(sed -n 's/^last_attempt=//p' "$T/data/adb/tricky_store/keybox.state" | tail -n 1)
ones=$(grep -c '^last_attempt=' "$T/data/adb/tricky_store/keybox.state" 2>/dev/null)
[ -z "$err_a" ] && [ -z "$err_b" ] && ok "a source with | & and \\ writes the state without an error" || no "a source with | & and \\ writes the state without an error (a=$err_a b=$err_b)"
[ "$first" != "$second" ] && [ "$ones" = 1 ] && ok "the second attempt advances last_attempt" || no "the second attempt advances last_attempt (first=$first second=$second lines=$ones)"
grep -qxF "last_source=$url_b" "$T/data/adb/tricky_store/keybox.state" && ok "the state file follows the current source" || no "the state file follows the current source"

out=$(env -u TMPDIR INTEGRITY_ROOT=$T sh "$mod/bin/keybox-validate.sh" "$FX/valid.xml" 2>&1) && ok "validator works with TMPDIR unset" || no "validator works with TMPDIR unset ($out)"
out=$(TMPDIR=$FX/does-not-exist INTEGRITY_SCRATCH=$FX/also-missing INTEGRITY_ROOT=$T sh "$mod/bin/keybox-validate.sh" "$FX/valid.xml" 2>&1) && ok "validator falls back when the scratch candidates are missing" || no "validator falls back when the scratch candidates are missing ($out)"
leftovers=$(find "$T" -name '.keybox-validate*' 2>/dev/null | wc -l | tr -d ' ')
[ "$leftovers" = 0 ] && ok "validator leaves no scratch directory behind" || no "validator leaves no scratch directory behind (found $leftovers)"

fresh
printf 'auto_keybox=0\n' > "$T/data/adb/tricky_store/integrity.conf"
printf 'garbage' > "$T/data/adb/tricky_store/keybox.xml"
cp "$FX/valid.xml" "$T/data/adb/tricky_store/keybox.prev.xml"
before=$(sha256sum "$T/data/adb/tricky_store/keybox.xml" | cut -d' ' -f1)
INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" heal >/dev/null 2>&1
after=$(sha256sum "$T/data/adb/tricky_store/keybox.xml" | cut -d' ' -f1)
[ "$before" = "$after" ] && ok "heal does nothing while auto_keybox=0" || no "heal does nothing while auto_keybox=0"

printf 'auto_keybox=1\nkeybox_url=\nkeybox_file=\n' > "$T/data/adb/tricky_store/integrity.conf"
INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" heal >/dev/null 2>&1
after=$(sha256sum "$T/data/adb/tricky_store/keybox.xml" | cut -d' ' -f1)
[ "$before" = "$after" ] && ok "heal does nothing without a configured source" || no "heal does nothing without a configured source"

printf 'auto_keybox=1\nkeybox_url=file://%s/valid.xml\n' "$FX" > "$T/data/adb/tricky_store/integrity.conf"
INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" heal >/dev/null 2>&1
INTEGRITY_ROOT=$T sh "$mod/bin/keybox-validate.sh" "$T/data/adb/tricky_store/keybox.xml" >/dev/null 2>&1 && ok "heal restores the previous keybox once the engine is on" || no "heal restores the previous keybox once the engine is on"

if command -v python3 >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
    fresh
    mkdir -p "$T/tls"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/tls/ca.key" -out "$T/tls/ca.pem" -subj "/CN=ZHA4968 test CA" -days 2 >/dev/null 2>&1
    openssl req -new -newkey rsa:2048 -nodes -keyout "$T/tls/server.key" -out "$T/tls/server.csr" -subj "/CN=127.0.0.1" >/dev/null 2>&1
    openssl x509 -req -in "$T/tls/server.csr" -CA "$T/tls/ca.pem" -CAkey "$T/tls/ca.key" -CAcreateserial -out "$T/tls/server.pem" -days 2 -extfile <(printf 'subjectAltName=IP:127.0.0.1') >/dev/null 2>&1
    python3 "$here/https-server.py" "$T/tls/server.pem" "$T/tls/server.key" "$T/tls/ports.json" "$FX/valid.xml" &
    tls_pid=$!
    trap 'kill $tls_pid 2>/dev/null' EXIT
    i=0
    while [ ! -s "$T/tls/ports.json" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    tls_port=$(sed -n 's/.*"tls": *\([0-9]*\).*/\1/p' "$T/tls/ports.json")
    cp "$FX/ec-only.xml" "$T/data/adb/tricky_store/keybox.xml"
    printf 'auto_keybox=1\nkeybox_url=https://127.0.0.1:%s/valid.xml\n' "$tls_port" > "$T/data/adb/tricky_store/integrity.conf"
    CURL_CA_BUNDLE=$T/tls/ca.pem INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" now >/dev/null 2>&1
    cmp -s "$FX/valid.xml" "$T/data/adb/tricky_store/keybox.xml" && ok "an https source with a trusted chain installs" || no "an https source with a trusted chain installs"
    before=$(sha256sum "$T/data/adb/tricky_store/keybox.xml" | cut -d' ' -f1)
    printf 'auto_keybox=1\nkeybox_url=https://127.0.0.1:%s/redir\n' "$tls_port" > "$T/data/adb/tricky_store/integrity.conf"
    CURL_CA_BUNDLE=$T/tls/ca.pem INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" now >/dev/null 2>&1
    after=$(sha256sum "$T/data/adb/tricky_store/keybox.xml" | cut -d' ' -f1)
    [ "$before" = "$after" ] && ok "an https redirect to plain http is refused" || no "an https redirect to plain http is refused"
    grep -q 'keybox fetch failed' "$T/data/adb/tricky_store/integrity.log" && ok "the refused redirect is logged" || no "the refused redirect is logged"
    printf 'auto_keybox=1\nkeybox_url=https://127.0.0.1:%s/valid.xml\nkeybox_sha256=deadbeef\n' "$tls_port" > "$T/data/adb/tricky_store/integrity.conf"
    CURL_CA_BUNDLE=$T/tls/ca.pem INTEGRITY_ROOT=$T sh "$mod/bin/keybox-fetch.sh" now >/dev/null 2>&1
    after=$(sha256sum "$T/data/adb/tricky_store/keybox.xml" | cut -d' ' -f1)
    [ "$before" = "$after" ] && ok "a pinned https source with the wrong hash is refused" || no "a pinned https source with the wrong hash is refused"
    kill $tls_pid 2>/dev/null
    trap - EXIT
else
    ok "https cases skipped (python3 or openssl missing)"
fi

out=$(INTEGRITY_ROOT=$T sh -c ". \"$mod/bin/keybox.sh\"; keybox_report")
printf '%s' "$out" | grep -q 'validation: valid' && ok "the report shows the validation verdict" || no "the report shows the validation verdict ($out)"
rm -f "$T/data/adb/tricky_store/keybox.xml"
out=$(INTEGRITY_ROOT=$T sh -c ". \"$mod/bin/keybox.sh\"; keybox_report")
printf '%s' "$out" | grep -q 'certificate-hack mode' && ok "missing keybox reports certificate-hack mode" || no "missing keybox reports certificate-hack mode"
printf '<Key algorithm="ecdsa">\n' > "$T/data/adb/tricky_store/keybox.xml"
out=$(INTEGRITY_ROOT=$T sh -c ". \"$mod/bin/keybox.sh\"; keybox_report")
printf '%s' "$out" | grep -q 'no rsa key' && ok "ecdsa-only keybox is called incomplete" || no "ecdsa-only keybox is called incomplete"
cp "$FX/valid.xml" "$T/data/adb/tricky_store/keybox.xml"
out=$(INTEGRITY_ROOT=$T sh -c ". \"$mod/bin/keybox.sh\"; keybox_report")
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

fresh
mkdir -p "$T/data/property"
printf 'x' > "$T/data/property/persistent_properties"
chmod 0666 "$T/data/property/persistent_properties"
printf '#!/bin/sh\necho\n' > "$T/bin/getprop"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > %s/setprop-args\n' "$T" > "$T/bin/setprop"
printf '#!/bin/sh\nprintf y > %s/pp.new; chmod 666 %s/pp.new; mv %s/pp.new %s/data/property/persistent_properties\n' "$T" "$T" "$T" "$T" > "$T/bin/resetprop"
chmod 755 "$T/bin/getprop" "$T/bin/setprop" "$T/bin/resetprop"
( export PATH=$T/bin:$PATH; sh "$mod/bin/fix-persist.sh" >/dev/null )
[ "$(stat -c %a "$T/data/property/persistent_properties")" = 600 ] && ok "re-arming adb leaves persistent_properties at 0600" || no "re-arming adb leaves persistent_properties at 0600"
grep -qx 'persist.sys.usb.config adb' "$T/setprop-args" 2>/dev/null && ok "lost adb config is re-armed through init" || no "lost adb config is re-armed through init"
fresh
cat > "$T/fixture.log" <<'EOF'
I/System.out( 8414): {
I/System.out( 8414):   "appIntegrity": {
I/System.out( 8414):     "appRecognitionVerdict": "PLAY_RECOGNIZED",
I/System.out( 8414):   },
I/System.out( 8414):   "deviceIntegrity": {
I/System.out( 8414):     "deviceRecognitionVerdict": ["MEETS_BASIC_INTEGRITY", "MEETS_DEVICE_INTEGRITY"],
I/System.out( 8414):   },
I/System.out( 8414):   "accountDetails": {
I/System.out( 8414):     "appLicensingVerdict": "LICENSED"
I/System.out( 8414):   },
I/System.out( 8414): }
EOF
line=$(sh "$mod/bin/verdict-parse.sh" < "$T/fixture.log")
printf '%s' "$line" | grep -q '"device":"MEETS_BASIC_INTEGRITY,MEETS_DEVICE_INTEGRITY"' && ok "verdict-parse keeps every device verdict" || no "verdict-parse keeps every device verdict (got $line)"
printf '%s' "$line" | grep -q '"app":"PLAY_RECOGNIZED"' && ok "verdict-parse reads the app verdict" || no "verdict-parse reads the app verdict"
printf '%s' "$line" | grep -q '"licensing":"LICENSED"' && ok "verdict-parse reads the licensing verdict" || no "verdict-parse reads the licensing verdict"
line=$(printf 'nothing useful
' | sh "$mod/bin/verdict-parse.sh")
printf '%s' "$line" | grep -q '"device":"none"' && ok "verdict-parse marks a missing verdict" || no "verdict-parse marks a missing verdict"

fresh
printf 'keybox_mode=auto
auto_verdict=0
' > "$T/data/adb/tricky_store/integrity.conf"
rm -f "$T/data/adb/tricky_store/verdicts.jsonl"
printf '#!/bin/sh\n[ "$1" = sys.boot_completed ] && echo 1\n' > "$T/bin/getprop"
for stub in sleep am input wm logcat; do printf '#!/bin/sh\nexit 0\n' > "$T/bin/$stub"; done
printf '#!/bin/sh\necho "  mCurrentFocus=Window{abc u0 com.henrikherzig.playintegritychecker/x}"\n' > "$T/bin/dumpsys"
chmod +x "$T/bin/"*
INTEGRITY_BIN=$mod/bin INTEGRITY_ROOT=$T PATH=$T/bin:$PATH sh "$mod/bin/boot-verdict.sh" >/dev/null 2>&1
[ -f "$T/data/adb/tricky_store/verdicts.jsonl" ] && no "auto_verdict=0 records nothing" || ok "auto_verdict=0 records nothing"


fresh
printf 'keybox_mode=software\nauto_keybox=0\nts_daemon=0\nauto_verdict=1\nkeep_adb=1\nverdict_delay=0\n' > "$T/data/adb/tricky_store/integrity.conf"
printf '<Key algorithm="ecdsa">\n<Key algorithm="rsa">\n' > "$T/data/adb/modules/playintegrityfix/software-keybox.xml"
printf '<Key algorithm="ecdsa">\n<Key algorithm="rsa">\n' > "$T/data/adb/tricky_store/keybox.xml"
n1=$( (ls "$T/data/adb/tricky_store"/keybox.xml.bak.* 2>/dev/null || true) | wc -l | tr -d ' ')
INTEGRITY_BIN=$mod/bin INTEGRITY_ROOT=$T sh -c '. "$INTEGRITY_BIN/keybox.sh"; keybox_apply_mode' >/dev/null 2>&1
n2=$( (ls "$T/data/adb/tricky_store"/keybox.xml.bak.* 2>/dev/null || true) | wc -l | tr -d ' ')
[ "$n1" = "$n2" ] && ok "an identical software keybox makes no new backup" || no "an identical software keybox makes no new backup ($n1 -> $n2)"

fresh
printf '#!/bin/sh\n[ "$1" = sys.boot_completed ] && echo 1\n' > "$T/bin/getprop"
printf '#!/bin/sh\necho "setprop $*" >> "%s/setprop.trace"\n' "$T" > "$T/bin/setprop"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/resetprop"
chmod +x "$T/bin/"*
printf 'keep_adb=0\n' > "$T/data/adb/tricky_store/integrity.conf"
mkdir -p "$T/data/property"
printf 'x' > "$T/data/property/persistent_properties"
chmod 0666 "$T/data/property/persistent_properties"
INTEGRITY_ROOT=$T PATH=$T/bin:$PATH sh "$mod/bin/fix-persist.sh" >/dev/null 2>&1
grep -q 'usb.config' "$T/setprop.trace" 2>/dev/null && no "keep_adb=0 leaves usb debugging alone" || ok "keep_adb=0 leaves usb debugging alone"
[ "$(stat -c %a "$T/data/property/persistent_properties")" = 600 ] && ok "fix-persist still repairs the mode with keep_adb=0" || no "fix-persist still repairs the mode with keep_adb=0"
printf 'keep_adb=1\n' > "$T/data/adb/tricky_store/integrity.conf"
chmod 0666 "$T/data/property/persistent_properties"
INTEGRITY_ROOT=$T PATH=$T/bin:$PATH sh "$mod/bin/fix-persist.sh" >/dev/null 2>&1
grep -q 'setprop persist.sys.usb.config adb' "$T/setprop.trace" 2>/dev/null && ok "keep_adb=1 re-arms adb" || no "keep_adb=1 re-arms adb"

fresh
printf 'keybox_mode=auto\nts_daemon=0\nauto_verdict=0\nkeep_adb=1\n' > "$T/data/adb/tricky_store/integrity.conf"
INTEGRITY_ROOT=$T PATH=$T/bin:$PATH sh "$mod/service.sh" >/dev/null 2>&1
grep -q 'ts_daemon=0: the TrickyStore loop is not started' "$T/data/adb/tricky_store/integrity.log" 2>/dev/null && ok "service.sh does not start the daemon loop by default" || no "service.sh does not start the daemon loop by default"

fresh
cp -a "$mod" "$T/mod"
printf '#!/bin/sh\necho run >> "%s/daemon.count"\n' "$T" > "$T/mod/daemon"
chmod 755 "$T/mod/daemon"
printf 'keybox_mode=auto\nts_daemon=1\nauto_verdict=0\nkeep_adb=1\n' > "$T/data/adb/tricky_store/integrity.conf"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T/bin/sleep"
INTEGRITY_ROOT=$T PATH=$T/bin:$PATH sh "$T/mod/service.sh" >/dev/null 2>&1
sleep 2
c1=$(wc -l < "$T/daemon.count" 2>/dev/null | tr -d ' ')
command sleep 2
c2=$(wc -l < "$T/daemon.count" 2>/dev/null | tr -d ' ')
[ "$c1" = 5 ] && [ "$c2" = 5 ] && ok "the daemon loop runs exactly five short-lived times, then stops" || no "the daemon loop runs exactly five short-lived times, then stops (got $c1 then $c2)"
pkill -f "$T/mod/service.sh" 2>/dev/null || true

fresh
printf '#!/bin/sh\n[ "$1" = sys.boot_completed ] && echo 1\n' > "$T/bin/getprop"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/am"
printf '#!/bin/sh\necho "input $*" >> "%s/input.trace"\n' "$T" > "$T/bin/input"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/wm"
printf '#!/bin/sh\necho "  mCurrentFocus=Window{abc u0 NotificationShade}"\n' > "$T/bin/dumpsys"
printf '#!/bin/sh\ncat "%s/fixture.log" 2>/dev/null\n' "$T" > "$T/bin/logcat"
chmod +x "$T/bin/"*
printf 'keybox_mode=auto\nauto_verdict=1\nverdict_delay=0\n' > "$T/data/adb/tricky_store/integrity.conf"
INTEGRITY_ROOT=$T PATH=$T/bin:$PATH sh "$mod/bin/boot-verdict.sh" >/dev/null 2>&1
grep -q 'skipped:NotificationShade' "$T/data/adb/tricky_store/verdicts.jsonl" 2>/dev/null && ok "boot-verdict records a skip when another window has focus" || no "boot-verdict records a skip when another window has focus"
grep -q 'input tap' "$T/input.trace" 2>/dev/null && no "boot-verdict does not tap without focus" || ok "boot-verdict does not tap without focus"

printf '#!/bin/sh\necho "  mCurrentFocus=Window{abc u0 com.henrikherzig.playintegritychecker/com.henrikherzig.playintegritychecker.MainActivity}"\n' > "$T/bin/dumpsys"
chmod +x "$T/bin/dumpsys"
: > "$T/input.trace"
printf 'I/System.out( 1): {\nI/System.out( 1):   "appIntegrity": { "appRecognitionVerdict": "PLAY_RECOGNIZED" },\nI/System.out( 1):   "deviceIntegrity": { "deviceRecognitionVerdict": ["MEETS_BASIC_INTEGRITY"] },\nI/System.out( 1):   "accountDetails": { "appLicensingVerdict": "LICENSED" } }\n' > "$T/fixture.log"
INTEGRITY_ROOT=$T PATH=$T/bin:$PATH sh "$mod/bin/boot-verdict.sh" >/dev/null 2>&1
grep -q 'input tap 360 594' "$T/input.trace" 2>/dev/null && ok "boot-verdict taps once the checker has focus" || no "boot-verdict taps once the checker has focus"
grep -q '"device":"MEETS_BASIC_INTEGRITY"' "$T/data/adb/tricky_store/verdicts.jsonl" 2>/dev/null && ok "boot-verdict records the parsed verdict when focused" || no "boot-verdict records the parsed verdict when focused"

printf '
%s passed, %s failed
' "$pass" "$fail"
[ "$fail" -eq 0 ]
