#!/system/bin/sh
# service.sh — module late_start service.
# Seeds config.json on first run, then applies CarrierConfig via app_process.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_PATH" ]; then
    echo '{"slots":{}}' > "$CONFIG_PATH"
    chmod 644 "$CONFIG_PATH"
fi

# Apply on boot if there's actual slot config (skip empty first-run seed).
if grep -q '"[0-9]"' "$CONFIG_PATH" 2>/dev/null; then
    sh "$MODDIR/bin/apply-root.sh" apply >/dev/null 2>&1
fi
