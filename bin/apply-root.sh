#!/system/bin/sh
# bin/apply-root.sh — runs the CarrierConfig applier as root via app_process.
#
# Outputs exactly ONE JSON line on stdout (app.js parses it).
# All diagnostics → /data/adb/carrier_ims/apply.log
#
# Usage: sh bin/apply-root.sh [apply|reset]
MODDIR=${0%/*}
DEX="$MODDIR/system/bin/Applier.dex"
LOG="/data/adb/carrier_ims/apply.log"

mkdir -p /data/adb/carrier_ims

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
emit() { echo "$1"; log "RESULT: $1"; }

log "=== apply-root invoked: ${1:-apply} ==="

if [ ! -f "$DEX" ]; then
    emit "{\"ok\":false,\"error\":\"dex 缺失: $DEX\"}"
    exit 1
fi

ACTION="${1:-apply}"

# Run app_process. Capture combined output to a temp file.
OUTFILE="/data/adb/carrier_ims/_applier_out.txt"
CLASSPATH="$DEX" app_process / Applier "$ACTION" >"$OUTFILE" 2>&1
RC=$?

log "app_process exit code: $RC"
log "--- app_process output start ---"
cat "$OUTFILE" >> "$LOG" 2>/dev/null
log "--- app_process output end ---"

# 137 = 128+9 = killed by SIGKILL (SELinux denial or OOM killer)
if [ "$RC" -eq 137 ]; then
    emit '{"ok":false,"error":"app_process 被 SIGKILL（SELinux 拦截）。查看 apply.log"}'
    exit 1
fi

# Other non-zero exit
if [ "$RC" -ne 0 ]; then
    ERRMSG=$(head -3 "$OUTFILE" 2>/dev/null | tr '\n' ' ' | sed "s/\"/'/g" | cut -c1-200)
    emit "{\"ok\":false,\"error\":\"exit $RC: $ERRMSG\"}"
    exit 1
fi

# Success — check if status.json was written with results
if [ -f /data/adb/carrier_ims/status.json ]; then
    # status.json has slots array; if any applied, success
    APPLIED=$(grep -o '"applied":[a-z]*' /data/adb/carrier_ims/status.json 2>/dev/null | head -1)
    log "status.json: $(cat /data/adb/carrier_ims/status.json)"
    emit '{"ok":true}'
else
    emit '{"ok":false,"error":"app_process 退出但未写 status.json"}'
fi
