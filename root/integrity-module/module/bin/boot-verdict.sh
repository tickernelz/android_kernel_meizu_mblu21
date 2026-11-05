#!/system/bin/sh
ROOT=${INTEGRITY_ROOT:-}
TS=$ROOT/data/adb/tricky_store
BIN=$(dirname -- "$0")
OUT=$TS/verdicts.jsonl
PKG=com.henrikherzig.playintegritychecker

. "$BIN/lib.sh"

[ "$(conf_get auto_verdict)" = 0 ] && exit 0

for _ in $(seq 1 120); do
    [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ] && break
    sleep 5
done
sleep 60

x=$(conf_get spic_tap_x)
y=$(conf_get spic_tap_y)
[ -n "$x" ] || x=360
[ -n "$y" ] || y=594

input keyevent KEYCODE_WAKEUP 2>/dev/null
wm dismiss-keyguard 2>/dev/null
sleep 1
am force-stop "$PKG" 2>/dev/null
logcat -c 2>/dev/null
am start -n "$PKG/.MainActivity" >/dev/null 2>&1
sleep 4
input tap "$x" "$y" 2>/dev/null
sleep 9

raw=$(logcat -d -v brief 2>/dev/null | grep -F 'System.out' | sed 's/^.*System.out( *[0-9]*): //')
mkdir -p "$TS" 2>/dev/null
printf '%s' "$raw" | sh "$BIN/verdict-parse.sh" >> "$OUT"
