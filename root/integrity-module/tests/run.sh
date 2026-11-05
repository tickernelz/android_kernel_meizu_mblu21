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
