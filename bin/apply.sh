#!/system/bin/sh
# bin/apply.sh — WebUI write+trigger path.
# Usage: sh /data/adb/modules/carrier_ims/bin/apply.sh <base64-json>
# Decodes the base64 config JSON to config.json, then broadcasts
# io.carrierims.action.APPLY_CONFIG so the priv-app re-applies. Returns a
# diagnostic JSON the WebUI can render.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"
PKG="io.carrierims.applier"

out() { echo "$1"; }

if [ -z "$1" ]; then
    out '{"ok":false,"error":"no input"}'
    exit 1
fi

mkdir -p "$CONFIG_DIR"

if command -v base64 >/dev/null 2>&1; then
    printf '%s' "$1" | base64 -d > "$CONFIG_PATH" 2>/dev/null
else
    printf '%s' "$1" | toybox base64 -d > "$CONFIG_PATH" 2>/dev/null
fi
if [ $? -ne 0 ]; then
    out '{"ok":false,"error":"base64 decode failed"}'
    exit 1
fi
chmod 644 "$CONFIG_PATH"
chown 0:0 "$CONFIG_PATH" 2>/dev/null

# Is the priv-app installed?
APP_INSTALLED="no"
if pm path "$PKG" >/dev/null 2>&1; then
    APP_INSTALLED="yes"
fi
# Trigger the priv-app to apply now. We don't rely on parsing am's output
# (it varies across Android versions); the priv-app writes status.json which
# the WebUI polls separately.
BR="sent"
if [ "$APP_INSTALLED" = "yes" ]; then
    am broadcast -a io.carrierims.action.APPLY_CONFIG --user 0 >/dev/null 2>&1
    BR="sent"
else
    BR="no_app"
fi

out "{\"ok\":true,\"app\":\"$APP_INSTALLED\",\"broadcast\":\"$BR\"}"
