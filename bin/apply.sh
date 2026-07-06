#!/system/bin/sh
# bin/apply.sh — WebUI write+trigger path.
# Usage: sh /data/adb/modules/carrier_ims/bin/apply.sh <base64-json>
# Decodes the base64 config JSON to config.json, then runs the root applier.
# Returns the applier's JSON result (ok/error) for the WebUI to display.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"

if [ -z "$1" ]; then
    echo '{"ok":false,"error":"no input"}'
    exit 1
fi

mkdir -p "$CONFIG_DIR"

if command -v base64 >/dev/null 2>&1; then
    printf '%s' "$1" | base64 -d > "$CONFIG_PATH" 2>/dev/null
else
    printf '%s' "$1" | toybox base64 -d > "$CONFIG_PATH" 2>/dev/null
fi
if [ $? -ne 0 ]; then
    echo '{"ok":false,"error":"base64 decode failed"}'
    exit 1
fi
chmod 644 "$CONFIG_PATH"

# Run the root applier and pass through its JSON result.
sh "$MODDIR/bin/apply-root.sh" apply
