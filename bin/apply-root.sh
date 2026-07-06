#!/system/bin/sh
# bin/apply-root.sh — runs the CarrierConfig applier as root via app_process.
#
# app_process runs as uid 0 (root) which holds MODIFY_PHONE_STATE implicitly.
# The applier writes status.json with per-slot results.
#
# Usage: sh bin/apply-root.sh [apply|reset]
MODDIR=${0%/*}
DEX="$MODDIR/system/bin/Applier.dex"

if [ ! -f "$DEX" ]; then
    echo '{"ok":false,"error":"dex not found at '"$DEX"'"}'
    exit 1
fi

ACTION="${1:-apply}"

# Capture stderr so we can report errors. The Java program writes status.json
# to /data/adb/carrier_ims/status.json regardless of success/failure.
ERRFILE="/data/adb/carrier_ims/applier_err.txt"
mkdir -p /data/adb/carrier_ims
CLASSPATH="$DEX" app_process / Applier "$ACTION" >"$ERRFILE.out" 2>"$ERRFILE"
RC=$?

if [ $RC -ne 0 ]; then
    ERRMSG=$(cat "$ERRFILE" "$ERRFILE.out" 2>/dev/null | head -5 | tr '\n' ' ' | sed 's/"/'\''/g')
    echo "{\"ok\":false,\"error\":\"exit $RC: $ERRMSG\"}"
else
    echo "{\"ok\":true,\"action\":\"$ACTION\"}"
fi
