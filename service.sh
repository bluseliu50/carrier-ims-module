#!/system/bin/sh
# service.sh — module late_start service (background daemon).
#
# Strategy: persistent carrier config overrides (overrideConfig persistent=true)
# survive reboot natively IF the apply succeeded with persistent=true. This
# daemon is the BACKSTOP for two cases persistent can't cover:
#   1. SIM change (拔卡/换卡) — new subId, persistent override doesn't map
#   2. Persistent apply failed (fell back to non-persistent)
#
# Runs forever in the background.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"
SIG_PATH="$CONFIG_DIR/.sim_sig"
LOG="$CONFIG_DIR/service.log"

mkdir -p "$CONFIG_DIR"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "=== service.sh started (pid $$) ==="

# Seed config on first run
if [ ! -f "$CONFIG_PATH" ]; then
    echo '{"slots":{}}' > "$CONFIG_PATH"
    chmod 644 "$CONFIG_PATH"
fi

has_config() { grep -q '"[0-9]"' "$CONFIG_PATH" 2>/dev/null; }

# Fingerprint of current SIM state — changes on 拔卡/换卡
sim_sig() {
    getprop gsm.sim.state_0
    getprop gsm.sim.state_1
    getprop gsm.operator.numeric
    getprop gsm.operator.numeric_1
    getprop gsm.sim.operator.numeric
    getprop gsm.sim.operator.numeric_1
    getprop gsm.operator.isoountry
    getprop gsm.sim.operator.alpha
}

do_apply() {
    has_config || { log "no slot config, skip"; return 0; }
    log "applying config..."
    if sh "$MODDIR/bin/apply-root.sh" apply >> "$LOG" 2>&1; then
        log "apply completed"
    else
        log "apply returned error"
    fi
}

# ---- Phase 1: boot apply ----
# Wait for telephony stack to come up. getprop gsm.* populates once the modem
# initializes. Give it generous time.
log "phase 1: waiting for SIM (up to 90s)"
i=0
while [ "$i" -lt 45 ]; do
    [ -n "$(getprop gsm.operator.numeric)" ] && break
    [ -n "$(getprop gsm.operator.numeric_1)" ] && break
    sleep 2
    i=$((i + 1))
done
log "telephony up after ~$((i * 2))s, applying"
do_apply
sim_sig > "$SIG_PATH"

# ---- Phase 2: SIM-change poll (every 15s) ----
log "phase 2: SIM-change poll loop (15s)"
while true; do
    sleep 15
    has_config || continue
    cur=$(sim_sig)
    prev=$(cat "$SIG_PATH" 2>/dev/null)
    if [ "$cur" != "$prev" ]; then
        log "SIM change: [$prev] → [$cur]"
        # Let the modem settle before re-applying
        sleep 8
        do_apply
        sim_sig > "$SIG_PATH"
    fi
done
