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

sh "$MODPATH/bin/targets.sh" merge || ui_print "- target list merge failed"
INTEGRITY_BIN="$MODPATH/bin"
. "$INTEGRITY_BIN/keybox.sh"
keybox_apply_mode

find "$MODPATH" -type f -name '*.sh' -exec chmod 755 {} + 2>/dev/null
chmod 755 "$MODPATH/tricky/daemon" "$MODPATH/tricky/machikado.arm64" "$MODPATH/tricky/machikado.arm" "$MODPATH/tricky/machikado.x64" 2>/dev/null
chmod 644 "$MODPATH/pif.prop" "$MODPATH/tricky/service.apk" "$MODPATH/classes.dex" 2>/dev/null
for f in integrity.conf target.txt security_patch.txt; do
    set_perm "$TS_DIR/$f" 0 0 644
done
ui_print "- done; reboot, then: su -c sh $MODPATH/bin/integrity.sh doctor"
