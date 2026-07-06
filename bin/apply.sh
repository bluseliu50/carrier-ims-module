#!/system/bin/sh
# bin/apply.sh — WebUI entry point.
# Decodes base64 config → writes config.json → runs apply-root.sh (app_process).
#
# Outputs exactly ONE JSON line on stdout.
# Usage: sh apply.sh <base64-config-json>
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"

if [ -z "$1" ]; then
    echo '{"ok":false,"error":"无输入参数"}'
    exit 1
fi

mkdir -p "$CONFIG_DIR"

# Decode base64 config
if command -v base64 >/dev/null 2>&1; then
    printf '%s' "$1" | base64 -d > "$CONFIG_PATH" 2>/dev/null
else
    printf '%s' "$1" | toybox base64 -d > "$CONFIG_PATH" 2>/dev/null
fi
if [ ! -s "$CONFIG_PATH" ]; then
    echo '{"ok":false,"error":"base64 解码失败"}'
    exit 1
fi
chmod 644 "$CONFIG_PATH"

# Run the app_process applier (apply-root.sh is in the same bin/ directory).
sh "$MODDIR/apply-root.sh" apply
