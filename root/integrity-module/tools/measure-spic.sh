#!/usr/bin/env bash
set -euo pipefail
adb_bin=${ADB:-adb}
args=()
if [ -n "${ADB_SERIAL:-}" ]; then
    args=(-s "$ADB_SERIAL")
fi
"$adb_bin" "${args[@]}" shell su -c 'sh /data/adb/modules/playintegrityfix/bin/integrity.sh verdict'
