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

delay=$(conf_get verdict_delay)
[ -n "$delay" ] || delay=60
sleep "$delay"

key=$(conf_get spic_unlock_key)
[ -n "$key" ] && input keyevent "$key" 2>/dev/null

x=$(conf_get spic_tap_x)
y=$(conf_get spic_tap_y)
[ -n "$x" ] || x=360
[ -n "$y" ] || y=594

am force-stop "$PKG" 2>/dev/null
am start -W -n "$PKG/.MainActivity" >/dev/null 2>&1

focus=""
for _ in $(seq 1 8); do
    focus=$(dumpsys window 2>/dev/null | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^}]*\)}.*/\1/p' | head -n 1)
    case $focus in
        *"$PKG"*) break ;;
    esac
    sleep 1
done

if [ -z "$focus" ]; then
    printf '{"ts":"%s","boot_id":"%s","device":"skipped:no-focus","app":"none","licensing":"none"}\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)" >> "$OUT"
    exit 0
fi

case $focus in
    *"$PKG"*) : ;;
    *)
        printf '{"ts":"%s","boot_id":"%s","device":"skipped:%s","app":"none","licensing":"none"}\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)" "$focus" >> "$OUT"
        exit 0
        ;;
esac

mark=$(date '+%m-%d %H:%M:%S.000')
input tap "$x" "$y" 2>/dev/null
sleep 9

raw=$(logcat -d -v brief -T "$mark" 2>/dev/null | grep -F 'System.out' | sed 's/^.*System.out( *[0-9]*): //')
mkdir -p "$TS" 2>/dev/null
printf '%s' "$raw" | sh "$BIN/verdict-parse.sh" >> "$OUT"
