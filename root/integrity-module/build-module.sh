#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

pif_url=https://github.com/osm0sis/PlayIntegrityFork/releases/download/v19/PlayIntegrityFork-v19.zip
pif_sha=83b4d5f32743805c5b5a69361d73b8ab9c095325e24f20711afa1abea837b58f
teesim_url=https://github.com/JingMatrix/TEESimulator/releases/download/canary-76/TEESimulator-v4.0-76-06f9f2e-Release.zip
teesim_sha=eb9af65a50f44bb4c887aeee7a2c110988cd54835ce80667488d09957aa3b376
stamp=1767225600

out=${1:-$root/mblu21-integrity.zip}
cache=${2:-${XDG_CACHE_HOME:-$HOME/.cache}/mblu21-integrity}

fetch() {
    url=$1
    sha=$2
    dest=$3
    if [ -f "$dest" ] && printf '%s  %s\n' "$sha" "$dest" | sha256sum -c - >/dev/null 2>&1; then
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    curl -fsSL -o "$dest.part" "$url"
    printf '%s  %s\n' "$sha" "$dest.part" | sha256sum -c - >/dev/null
    mv "$dest.part" "$dest"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fetch "$pif_url" "$pif_sha" "$cache/PlayIntegrityFork-v19.zip"
fetch "$teesim_url" "$teesim_sha" "$cache/TEESimulator-canary76.zip"

mkdir -p "$work/pif" "$work/teesim" "$work/stage/zygisk" "$work/stage/teesim/arm64-v8a"
unzip -q "$cache/PlayIntegrityFork-v19.zip" -d "$work/pif"
unzip -q "$cache/TEESimulator-canary76.zip" -d "$work/teesim"
cp -a "$here/module/." "$work/stage/"

for f in classes.dex common_func.sh common_setup.sh app_replace_list.txt example.pif.prop; do
    cp "$work/pif/$f" "$work/stage/"
done
cp "$work/pif/post-fs-data.sh" "$work/stage/pif-post-fs-data.sh"
cp "$work/pif/service.sh" "$work/stage/pif-service.sh"
cp "$work/pif/zygisk/"*.so "$work/stage/zygisk/"
mkdir -p "$work/stage/META-INF/com/google/android"
cp "$work/pif/META-INF/com/google/android/update-binary" "$work/stage/META-INF/com/google/android/update-binary"
cp "$work/pif/META-INF/com/google/android/updater-script" "$work/stage/META-INF/com/google/android/updater-script"

for f in daemon classes.dex config.default.json service.sh; do
    cp "$work/teesim/$f" "$work/stage/teesim/$f"
done
for f in inject libteesim_keymint.so libteesim_keystore.so libteesim_logcat.so teesim-uds; do
    cp "$work/teesim/arm64-v8a/$f" "$work/stage/teesim/arm64-v8a/$f"
done

{
    printf '# merged by build-module.sh from teesim/sepolicy.rule\n'
    grep -vE '^[[:space:]]*(#|$)' "$work/teesim/sepolicy.rule"
} > "$work/stage/sepolicy.rule"
cp "$work/teesim/sepolicy.rule" "$work/stage/teesim/sepolicy.rule.upstream"

chmod 755 "$work/stage"/*.sh "$work/stage"/bin/*.sh "$work/stage/teesim/daemon" "$work/stage/teesim/service.sh" \
    "$work/stage/teesim/arm64-v8a/inject" "$work/stage/teesim/arm64-v8a/teesim-uds"
chmod 644 "$work/stage/classes.dex" "$work/stage/pif.prop" "$work/stage/target.txt" \
    "$work/stage/security_patch.txt" "$work/stage/integrity.conf" "$work/stage/teesim/classes.dex" \
    "$work/stage/teesim/config.default.json" "$work/stage/teesim/arm64-v8a/libteesim_keymint.so" \
    "$work/stage/teesim/arm64-v8a/libteesim_keystore.so" "$work/stage/teesim/arm64-v8a/libteesim_logcat.so"
find "$work/stage" -exec touch -m -d "@$stamp" {} +

rm -f "$out"
( cd "$work/stage" && zip -q -X -r "$out" . )
printf 'built %s\n' "$out"
sha256sum "$out"
