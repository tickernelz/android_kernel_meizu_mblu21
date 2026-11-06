#!/system/bin/sh
# shellcheck disable=SC2034
INTEGRITY_ROOT=${INTEGRITY_ROOT:-}
TS_DIR=$INTEGRITY_ROOT/data/adb/tricky_store
MOD_DIR=$INTEGRITY_ROOT/data/adb/modules/playintegrityfix
CONF=$TS_DIR/integrity.conf
KEYBOX=$TS_DIR/keybox.xml
TARGETS_FILE=$TS_DIR/target.txt
SP_FILE=$TS_DIR/security_patch.txt
PIF_PROP=$MOD_DIR/pif.prop
LOG_FILE=$TS_DIR/integrity.log
CHECKER_PKG=com.henrikherzig.playintegritychecker
TEESIM_DIR=$INTEGRITY_ROOT/data/adb/teesim
TEESIM_CONF=$TEESIM_DIR/config.json
TEESIM_KEYBOX=$TEESIM_DIR/keybox.xml
TEESIM_MODULE=$INTEGRITY_ROOT/data/adb/modules/teesim

conf_get() {
    [ -f "$CONF" ] || return 0
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONF" | tail -n 1 | tr -d '\r'
}

file_get() {
    [ -f "$1" ] || return 0
    sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" | tail -n 1 | tr -d '\r'
}

file_set() {
    f=$1
    k=$2
    v=$3
    [ -f "$f" ] || return 1
    if grep -q "^[[:space:]]*${k}[[:space:]]*=" "$f"; then
        sed -i "s|^[[:space:]]*${k}[[:space:]]*=.*|$k=$v|" "$f"
    else
        printf '%s=%s\n' "$k" "$v" >> "$f"
    fi
}

log_line() {
    mkdir -p "$TS_DIR" 2>/dev/null
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
    printf '%s\n' "$*"
}
