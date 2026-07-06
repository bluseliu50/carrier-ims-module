#!/system/bin/sh
# bin/apply-root.sh — runs the CarrierConfig applier as root via app_process.
#
# No priv-app, no /system overlay, zero boot-loop risk. The applier dex is
# CI-built and shipped inside the module zip. app_process runs as uid 0 (root),
# which holds MODIFY_PHONE_STATE implicitly.
#
# Usage: sh bin/apply-root.sh [apply|reset]
MODDIR=${0%/*}
DEX="$MODDIR/system/bin/Applier.dex"

if [ ! -f "$DEX" ]; then
    echo '{"ok":false,"error":"applier dex not found"}'
    exit 1
fi

ACTION="${1:-apply}"
CLASSPATH="$DEX" app_process / Applier "$ACTION" 2>/dev/null
echo "{\"ok\":true,\"action\":\"$ACTION\"}"
