#!/system/bin/sh
# bin/apply.sh — WebUI write+trigger path.
# Usage: sh /data/adb/modules/carrier_ims/bin/apply.sh <base64-json>
# Decodes the base64 config JSON to /data/adb/carrier_ims/config.json, then
# broadcasts io.carrierims.action.APPLY_CONFIG so the priv-app re-applies.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"

if [ -z "$1" ]; then
    echo "usage: apply.sh <base64-json>" >&2
    exit 1
fi

mkdir -p "$CONFIG_DIR"

# Decode base64 (toybox/base64 present on Android) and write config.
if command -v base64 >/dev/null 2>&1; then
    printf '%s' "$1" | base64 -d > "$CONFIG_PATH" 2>/dev/null
else
    # Fallback: toybox decode alias.
    printf '%s' "$1" | toybox base64 -d > "$CONFIG_PATH" 2>/dev/null
fi

if [ $? -ne 0 ]; then
    echo '{"ok":false,"error":"base64 decode failed"}'
    exit 1
fi

chmod 644 "$CONFIG_PATH"
chown 0:0 "$CONFIG_PATH" 2>/dev/null

# Trigger the priv-app to apply immediately. The receiver is protected by
# android:permission="android.permission.SHELL"; root am qualifies.
am broadcast -a io.carrierims.action.APPLY_CONFIG --user 0 >/dev/null 2>&1

echo '{"ok":true}'
