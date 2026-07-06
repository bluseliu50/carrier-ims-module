#!/system/bin/sh
# service.sh — module late_start service.
#
# Runs in background. Waits for SIM ready → applies config → polls for
# SIM changes (拔卡/换卡) and re-applies automatically.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"
STATE_PATH="$CONFIG_DIR/.last_state"
LOG="$CONFIG_DIR/service.log"

mkdir -p "$CONFIG_DIR"

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "=== service.sh started ==="

# Seed config on first run
if [ ! -f "$CONFIG_PATH" ]; then
    echo '{"slots":{}}' > "$CONFIG_PATH"
    chmod 644 "$CONFIG_PATH"
fi

has_config() {
    grep -q '"[0-9]"' "$CONFIG_PATH" 2>/dev/null
}

# SIM readiness: check both slots' SIM state via getprop
sim_ready() {
    local s0 s1
    s0=$(getprop gsm.sim.state_0)
    s1=$(getprop gsim.sim.state_1)
    [ "$s0" = "READY" ] || [ "$s1" = "READY" ] || \
    [ "$(getprop gsm.sim.state)" = "READY" ]
}

# Snapshot of SIM identifiers for change detection
sim_signature() {
    getprop gsm.sim.state_0; getprop gsm.sim.state_1; \
    getprop gsm.operator.numeric; getprop gsm.operator.numeric_1; \
    getprop gsm.sim.operator.numeric; getprop gsm.sim.operator.numeric_1
}

do_apply() {
    has_config || return 0
    log "applying config..."
    if sh "$MODDIR/bin/apply-root.sh" apply >> "$LOG" 2>&1; then
        log "apply ok"
    else
        log "apply returned non-zero"
    fi
}

# ---- Phase 1: wait for SIM ready (up to ~2 min) ----
WAIT=0
while [ "$WAIT" -lt 60 ]; do
    if sim_ready; then
        log "SIM ready after ~$((WAIT * 2))s"
        break
    fi
    sleep 2
    WAIT=$((WAIT + 1))
done

do_apply
sim_signature > "$STATE_PATH"

# ---- Phase 2: poll for SIM changes every 20s ----
log "entering SIM-change poll loop"
while true; do
    sleep 20
    has_config || continue
    CUR=$(sim_signature)
    PREV=$(cat "$STATE_PATH" 2>/dev/null)
    if [ "$CUR" != "$PREV" ]; then
        log "SIM change detected: [$PREV] → [$CUR]"
        # Give the modem a moment to settle
        sleep 5
        do_apply
        sim_signature > "$STATE_PATH"
    fi
done
