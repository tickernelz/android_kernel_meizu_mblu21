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

MIGRATED=$TS_DIR/.migrated-v1.2.0
if [ ! -f "$MIGRATED" ] && [ "$(sed -n 's/^ts_daemon=//p' "$TS_DIR/integrity.conf" 2>/dev/null | tail -n 1)" = 0 ]; then
    sed -i 's/^ts_daemon=.*/ts_daemon=1/' "$TS_DIR/integrity.conf"
    ui_print "- ts_daemon was 0 from v1.1.0; turned the certificate provider back on"
fi
: > "$MIGRATED"
chmod 644 "$MIGRATED" 2>/dev/null

sh "$MODPATH/bin/targets.sh" merge || ui_print "- target list merge failed"
INTEGRITY_BIN="$MODPATH/bin"
. "$INTEGRITY_BIN/keybox.sh"
keybox_apply_mode

find "$MODPATH" -type f -name '*.sh' -exec chmod 755 {} + 2>/dev/null
chmod 755 "$MODPATH/daemon" "$MODPATH/machikado" "$MODPATH/mazoku" 2>/dev/null
chmod 644 "$MODPATH/pif.prop" "$MODPATH/service.apk" "$MODPATH/libtricky_store.so" "$MODPATH/classes.dex" 2>/dev/null
for f in integrity.conf target.txt security_patch.txt; do
    set_perm "$TS_DIR/$f" 0 0 644
done
ui_print "- done; reboot, then: adb shell sh $MODPATH/bin/integrity.sh doctor"
