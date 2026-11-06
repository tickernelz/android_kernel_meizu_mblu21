#!/system/bin/sh
bin_dir=$(dirname -- "$0")
: "${INTEGRITY_BIN:=$bin_dir}"
. "$INTEGRITY_BIN/lib.sh"

DAEMON_BIN=$MOD_DIR/daemon
PIDFILE=$TS_DIR/ts_daemon.pid
SUPERVISOR_PIDFILE=$TS_DIR/ts_daemon.supervisor.pid
BOOT_WAIT=${TS_BOOT_WAIT:-180}
KEYSTORE_WAIT=${TS_KEYSTORE_WAIT:-90}
RESTART_MIN=${TS_RESTART_MIN:-5}
RESTART_MAX=${TS_RESTART_MAX:-60}
STABLE_RUN=${TS_STABLE_RUN:-60}
LOOP_MAX=${TS_LOOP_MAX:-0}

daemon_pid() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$pid"
            return 0
        fi
    fi
    pid=$(pidof TrickyStore 2>/dev/null | awk '{print $1}')
    [ -n "$pid" ] || return 1
    printf '%s\n' "$pid"
}

supervisor_pid() {
    [ -f "$SUPERVISOR_PIDFILE" ] || return 1
    pid=$(cat "$SUPERVISOR_PIDFILE" 2>/dev/null)
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    printf '%s\n' "$pid"
}

wait_for() {
    limit=$1
    shift
    spent=0
    while [ "$spent" -lt "$limit" ]; do
        if "$@"; then
            return 0
        fi
        sleep 2
        spent=$((spent + 2))
    done
    "$@"
}

boot_done() {
    [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ]
}

keystore_up() {
    [ -n "$(pidof keystore2 2>/dev/null)" ]
}

mapped_count() {
    pid=$1
    grep -c libtricky_store "/proc/$pid/maps" 2>/dev/null | tr -d ' '
}

recent_launches() {
    logcat -d -v brief 2>/dev/null | grep -c 'tricky_store.MainKt'
}

status() {
    enabled=$(conf_get ts_daemon)
    : "${enabled:=1}"
    printf 'configured: ts_daemon=%s\n' "$enabled"
    if [ ! -f "$DAEMON_BIN" ]; then
        printf '[fail] %s is missing\n' "$DAEMON_BIN"
        return 1
    fi
    sup=$(supervisor_pid 2>/dev/null)
    pid=$(daemon_pid 2>/dev/null)
    if [ "$enabled" != 1 ]; then
        printf '[ok] the provider is switched off on request (ts_daemon=%s)\n' "$enabled"
        if [ -n "$pid" ]; then
            printf '[warn] a daemon from an earlier run is still alive: pid=%s\n' "$pid"
        fi
        return 0
    fi
    rc=0
    if [ -n "$sup" ]; then
        printf '[ok] supervisor pid=%s\n' "$sup"
    else
        printf '[fail] no supervisor process, so the provider is not being restarted\n'
        rc=1
    fi
    if [ -n "$pid" ]; then
        maps=$(mapped_count "$pid")
        printf '[ok] daemon alive pid=%s, libtricky_store mapped %s time(s)\n' "$pid" "${maps:-0}"
        if [ "${maps:-0}" -lt 1 ]; then
            printf '[fail] the daemon is up but libtricky_store.so is not mapped, so it cannot serve a chain\n'
            rc=1
        fi
    else
        printf '[fail] no daemon process: the keybox is not served to keystore\n'
        rc=1
    fi
    printf '[info] launches in the last 15 minutes: %s\n' "$(recent_launches)"
    for key in 'ts_daemon: started' 'ts_daemon: exited' 'ts_daemon: restarting'; do
        line=$(grep -F "$key" "$LOG_FILE" 2>/dev/null | tail -n 1)
        [ -n "$line" ] && printf '[info] last %s\n' "$line"
    done
    return $rc
}

run_once() {
    [ -f "$DAEMON_BIN" ] || { log_line '[fail] the TrickyStore daemon is missing'; return 1; }
    started=$(date +%s)
    ( cd "$MOD_DIR" && exec ./daemon ) &
    pid=$!
    printf '%s\n' "$pid" > "$PIDFILE"
    log_line "ts_daemon: started $DAEMON_BIN pid=$pid"
    wait "$pid"
    rc=$?
    rm -f "$PIDFILE" 2>/dev/null
    log_line "ts_daemon: exited rc=$rc after $(( $(date +%s) - started ))s"
    return $rc
}

loop() {
    enabled=$(conf_get ts_daemon)
    : "${enabled:=1}"
    if [ "$enabled" != 1 ]; then
        log_line "ts_daemon=$enabled: the provider loop is not started"
        return 0
    fi
    if [ ! -f "$DAEMON_BIN" ]; then
        log_line "ts_daemon: $DAEMON_BIN is missing, the provider loop is not started"
        return 1
    fi
    existing=$(supervisor_pid 2>/dev/null)
    if [ -n "$existing" ] && [ "$existing" != "$$" ]; then
        log_line "ts_daemon: supervisor pid=$existing already runs, this one exits"
        return 0
    fi
    printf '%s\n' "$$" > "$SUPERVISOR_PIDFILE"
    trap 'rm -f "$SUPERVISOR_PIDFILE" 2>/dev/null' EXIT INT TERM HUP
    wait_for "$BOOT_WAIT" boot_done || log_line "ts_daemon: boot_completed still unset after ${BOOT_WAIT}s, starting anyway"
    wait_for "$KEYSTORE_WAIT" keystore_up || log_line "ts_daemon: keystore2 still absent after ${KEYSTORE_WAIT}s, starting anyway"
    backoff=$RESTART_MIN
    runs=0
    while :; do
        enabled=$(conf_get ts_daemon)
        : "${enabled:=1}"
        if [ "$enabled" != 1 ]; then
            log_line "ts_daemon: switched off at runtime (ts_daemon=$enabled), the loop stops"
            break
        fi
        started=$(date +%s)
        ( cd "$MOD_DIR" && exec ./daemon ) &
        pid=$!
        printf '%s\n' "$pid" > "$PIDFILE"
        log_line "ts_daemon: started $DAEMON_BIN pid=$pid"
        wait "$pid"
        rc=$?
        rm -f "$PIDFILE" 2>/dev/null
        elapsed=$(( $(date +%s) - started ))
        log_line "ts_daemon: exited rc=$rc after ${elapsed}s"
        runs=$((runs + 1))
        if [ "$LOOP_MAX" -gt 0 ] && [ "$runs" -ge "$LOOP_MAX" ]; then
            log_line "ts_daemon: stopped after ${runs} run(s) because TS_LOOP_MAX=$LOOP_MAX"
            break
        fi
        if [ "$elapsed" -ge "$STABLE_RUN" ]; then
            backoff=$RESTART_MIN
        fi
        log_line "ts_daemon: restarting in ${backoff}s"
        sleep "$backoff"
        backoff=$((backoff * 2))
        [ "$backoff" -le "$RESTART_MAX" ] || backoff=$RESTART_MAX
    done
    rm -f "$SUPERVISOR_PIDFILE" 2>/dev/null
    return 0
}

case ${1:-status} in
    loop) loop ;;
    once) run_once ;;
    status) status ;;
    *)
        printf 'usage: %s loop|once|status\n' "$0" >&2
        exit 2
        ;;
esac
