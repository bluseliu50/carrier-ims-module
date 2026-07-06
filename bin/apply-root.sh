#!/system/bin/sh
# apply-root.sh — runs the CarrierConfig applier as root, then drops to shell uid.
#
# The Java program prints result JSON to stdout. This script captures it,
# writes status.json (as root), and emits exactly ONE JSON line for app.js.
#
# Usage: sh apply-root.sh [apply|reset]
MODROOT=/data/adb/modules/carrier_ims
DEX="$MODROOT/system/bin/Applier.dex"
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
OUTFILE="/data/adb/carrier_ims/_applier_out.txt"

# Run app_process — Java program drops to shell uid internally, prints JSON to stdout.
CLASSPATH="$DEX" app_process / Applier "$ACTION" >"$OUTFILE" 2>>"$LOG"
RC=$?

log "app_process exit code: $RC"
log "--- stdout ---"
cat "$OUTFILE" >> "$LOG" 2>/dev/null
log "--- end ---"

# 137 = SIGKILL — root process still being killed
if [ "$RC" -eq 137 ]; then
    emit '{"ok":false,"error":"app_process SIGKILL（进程被杀）"}'
    exit 1
fi

if [ "$RC" -ne 0 ]; then
    ERRMSG=$(head -3 "$OUTFILE" 2>/dev/null | tr '\n' ' ' | sed "s/\"/'/g" | cut -c1-200)
    emit "{\"ok\":false,\"error\":\"exit $RC: $ERRMSG\"}"
    exit 1
fi

# Parse stdout — should be a JSON line
OUTPUT=$(cat "$OUTFILE" 2>/dev/null)
if [ -z "$OUTPUT" ]; then
    emit '{"ok":false,"error":"app_process 无输出"}'
    exit 1
fi

# Error JSON from Java (has "ok":false)
if echo "$OUTPUT" | grep -q '"ok":false'; then
    ERR=$(echo "$OUTPUT" | grep -o '"error":"[^"]*"' | head -1 | sed 's/"error":"//;s/"$//')
    emit "{\"ok\":false,\"error\":\"$ERR\"}"
    exit 1
fi

# Success — write status.json from the output (last line with JSON)
echo "$OUTPUT" | tail -1 > /data/adb/carrier_ims/status.json
emit '{"ok":true}'
