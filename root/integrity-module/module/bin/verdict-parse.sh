#!/system/bin/sh
raw=$(cat)
[ -n "$raw" ] || raw='{}'

dev=$(printf '%s' "$raw" | grep -o '"deviceRecognitionVerdict": \[[^]]*\]' | sed 's/.*\[//;s/\].*//;s/"//g;s/ //g')
app=$(printf '%s' "$raw" | grep -o '"appRecognitionVerdict": "[A-Z_]*"' | sed 's/.*"appRecognitionVerdict": "//;s/"$//')
lic=$(printf '%s' "$raw" | grep -o '"appLicensingVerdict": "[A-Z_]*"' | sed 's/.*"appLicensingVerdict": "//;s/"$//')
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)

printf '{"ts":"%s","boot_id":"%s","device":"%s","app":"%s","licensing":"%s"}\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "${boot:-unknown}" "${dev:-none}" "${app:-none}" "${lic:-none}"
