#!/system/bin/sh
# bin/apply.sh — applies CarrierConfig overrides via `cmd phone cc set-value -p`.
#
# This is the pure-shell approach: no app_process, no dex, no priv-app, no
# /system overlay. `cmd phone cc` is a built-in Android shell command (since
# Android 11) that directly overrides carrier config values from the phone
# service. Root (uid 0) has permission to run it. The -p flag makes the
# override persistent across reboots.
#
# Usage: sh /data/adb/modules/carrier_ims/bin/apply.sh <base64-json>
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"
STATUS_PATH="$CONFIG_DIR/status.json"

if [ -z "$1" ]; then
    echo '{"ok":false,"error":"no input"}'
    exit 1
fi

mkdir -p "$CONFIG_DIR"

# Decode base64 config
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

# Apply the config. Each toggle in config.json maps to one or more
# `cmd phone cc set-value -p <key> <value>` calls.
sh "$MODDIR/bin/cc-apply.sh" "$CONFIG_PATH" "$STATUS_PATH"
