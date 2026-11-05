#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

ts_url=https://github.com/5ec1cff/TrickyStore/releases/download/1.4.1/Tricky-Store-v1.4.1-245-72b2e84-release.zip
ts_sha=2f5e73fcba0e4e43b6e96b38f333cbe394873e3a81cf8fe1b831c2fbd6c46ea9
pif_url=https://github.com/osm0sis/PlayIntegrityFork/releases/download/v19/PlayIntegrityFork-v19.zip
pif_sha=83b4d5f32743805c5b5a69361d73b8ab9c095325e24f20711afa1abea837b58f
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
fetch "$ts_url" "$ts_sha" "$cache/Tricky-Store-1.4.1.zip"
fetch "$pif_url" "$pif_sha" "$cache/PlayIntegrityFork-v19.zip"

mkdir -p "$work/ts" "$work/pif" "$work/stage/zygisk"
unzip -q "$cache/Tricky-Store-1.4.1.zip" -d "$work/ts"
unzip -q "$cache/PlayIntegrityFork-v19.zip" -d "$work/pif"
cp -a "$here/module/." "$work/stage/"

for f in service.apk daemon mazoku machikado.arm64 sepolicy.rule; do
    cp "$work/ts/$f" "$work/stage/$f"
done
cp "$work/ts/machikado.arm64" "$work/stage/machikado"
cp "$work/ts/lib/arm64/libtricky_store.so" "$work/stage/libtricky_store.so"
cp "$work/ts/keybox.xml" "$work/stage/software-keybox.xml"

for f in service.apk daemon mazoku machikado.arm64 lib/arm64/libtricky_store.so keybox.xml; do
    want=$(cat "$work/ts/$f.sha256")
    got=$(sha256sum "$work/ts/$f" | cut -d' ' -f1)
    [ "$want" = "$got" ] || { echo "upstream sha256 mismatch for $f" >&2; exit 1; }
done

for f in classes.dex common_func.sh common_setup.sh app_replace_list.txt example.pif.prop; do
    cp "$work/pif/$f" "$work/stage/"
done
cp "$work/pif/post-fs-data.sh" "$work/stage/pif-post-fs-data.sh"
cp "$work/pif/service.sh" "$work/stage/pif-service.sh"
cp "$work/pif/zygisk/"*.so "$work/stage/zygisk/"
mkdir -p "$work/stage/META-INF/com/google/android"
cp "$work/pif/META-INF/com/google/android/update-binary" "$work/stage/META-INF/com/google/android/update-binary"
cp "$work/pif/META-INF/com/google/android/updater-script" "$work/stage/META-INF/com/google/android/updater-script"

chmod 755 "$work/stage"/*.sh "$work/stage"/bin/*.sh "$work/stage"/daemon "$work/stage"/machikado "$work/stage"/mazoku
chmod 644 "$work/stage/service.apk" "$work/stage/libtricky_store.so" "$work/stage/classes.dex" "$work/stage/pif.prop" "$work/stage/target.txt" "$work/stage/security_patch.txt" "$work/stage/integrity.conf" "$work/stage/software-keybox.xml"
find "$work/stage" -exec touch -m -d "@$stamp" {} +

rm -f "$out"
( cd "$work/stage" && zip -q -X -r "$out" . )
printf 'built %s\n' "$out"
sha256sum "$out"
