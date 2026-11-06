#!/system/bin/sh
MODPATH="${MODPATH:-/data/adb/modules/playintegrityfix}"
TS_DIR=/data/adb/tricky_store
ui_print() { echo "$1"; }

set_perm() {
    chown "$2:$3" "$1" 2>/dev/null
    chmod "$4" "$1" 2>/dev/null
}

ui_print "- mblu21 integrity: TrickyStore + Play Integrity Fork"
mkdir -p "$TS_DIR"
LEGACY=$TS_DIR/legacy-$(date +%Y%m%d%H%M%S)

if [ -f /data/adb/modules/tricky_store/module.prop ]; then
    mkdir -p "$LEGACY"
    mv /data/adb/modules/tricky_store "$LEGACY/tricky_store" 2>/dev/null
    ui_print "- the module that held /data/adb/tricky_store moved to $LEGACY/tricky_store"
fi

for ART in alwaysstrong hbk boot_hash.bin boot_key.bin persistent_keys logs pif.prop; do
    [ -e "$TS_DIR/$ART" ] || continue
    mkdir -p "$LEGACY"
    mv "$TS_DIR/$ART" "$LEGACY/" 2>/dev/null
done

if [ -f "$TS_DIR/keybox.xml" ]; then
    ui_print "- keeping the keybox already at $TS_DIR/keybox.xml"
else
    ui_print "- no keybox: TrickyStore runs certificate-hack mode only"
fi

for f in integrity.conf target.txt security_patch.txt; do
    if [ -f "$TS_DIR/$f" ]; then
        ui_print "- keeping the existing $TS_DIR/$f"
    else
        cp -f "$MODPATH/$f" "$TS_DIR/$f"
    fi
done

MIGRATED=$TS_DIR/.migrated-v1.3.0
if [ ! -f "$MIGRATED" ]; then
    sed -i '/^ts_daemon=/d' "$TS_DIR/integrity.conf" 2>/dev/null
    if [ "$(sed -n 's/^auto_keybox=//p' "$TS_DIR/integrity.conf" 2>/dev/null | tail -n 1)" = 0 ]; then
        sed -i 's/^auto_keybox=.*/auto_keybox=1/' "$TS_DIR/integrity.conf"
        ui_print "- auto_keybox was 0; the scheduled refresh is on by default now"
    fi
    if [ "$(sed -n 's/^keybox_fetch_interval_h=//p' "$TS_DIR/integrity.conf" 2>/dev/null | tail -n 1)" = 24 ]; then
        sed -i 's/^keybox_fetch_interval_h=.*/keybox_fetch_interval_h=6/' "$TS_DIR/integrity.conf"
        ui_print "- refresh interval moved from 24 h to 6 h (one request per interval)"
    fi
    if ! grep -q '^keybox_catalog=' "$TS_DIR/integrity.conf" 2>/dev/null; then
        printf 'keybox_catalog=https://rawbin.dpejoh.com/catalog\n' >> "$TS_DIR/integrity.conf"
    fi
    : > "$MIGRATED"
    chmod 644 "$MIGRATED" 2>/dev/null
fi

sh "$MODPATH/bin/targets.sh" merge || ui_print "- target list merge failed"
TEESIM_DIR=/data/adb/teesim
mkdir -p "$TEESIM_DIR"
if [ ! -f "$TEESIM_DIR/config.json" ]; then
    cp -f "$MODPATH/teesim/config.default.json" "$TEESIM_DIR/config.json"
    sed -i 's/"mode"[[:space:]]*:[[:space:]]*"patch"/"mode": "generation"/' "$TEESIM_DIR/config.json"
    ui_print "- seeded $TEESIM_DIR/config.json in generation mode"
fi
if [ ! -f "$TEESIM_DIR/keybox.xml" ] && [ -f /data/adb/tricky_store/keybox.xml ]; then
    cp -f /data/adb/tricky_store/keybox.xml "$TEESIM_DIR/keybox.xml"
    chmod 600 "$TEESIM_DIR/keybox.xml"
    ui_print "- adopted the keybox already on the phone into $TEESIM_DIR"
fi
chmod 0700 "$TEESIM_DIR" 2>/dev/null

INTEGRITY_BIN="$MODPATH/bin"
. "$INTEGRITY_BIN/keybox.sh"
keybox_apply_mode
sh "$INTEGRITY_BIN/targets.sh" teesim || ui_print "- teesim app list sync failed"

find "$MODPATH" -type f -name '*.sh' -exec chmod 755 {} + 2>/dev/null
chmod 755 "$MODPATH/daemon" "$MODPATH/machikado" "$MODPATH/mazoku" 2>/dev/null
chmod 644 "$MODPATH/pif.prop" "$MODPATH/service.apk" "$MODPATH/libtricky_store.so" "$MODPATH/classes.dex" 2>/dev/null
for f in integrity.conf target.txt security_patch.txt; do
    set_perm "$TS_DIR/$f" 0 0 644
done
ui_print "- done; reboot, then: adb shell sh $MODPATH/bin/integrity.sh doctor"
