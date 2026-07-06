#!/system/bin/sh
# service.sh — module late_start service (KernelSU/Magisk/APatch all run this).
# Seeds config.json on first run, then applies CarrierConfig as root.
# No priv-app needed: app_process runs as uid 0 which holds MODIFY_PHONE_STATE.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_PATH" ]; then
    echo '{"slots":{}}' > "$CONFIG_PATH"
    chmod 644 "$CONFIG_PATH"
fi

# Apply on boot (covers the "每次启动重新执行" problem — no manual trigger needed).
# Only if there are actual slot configs (skip the empty first-run seed).
SLOTS=$(grep -o '"slots"' "$CONFIG_PATH" 2>/dev/null)
HAS_CFG=$(grep -o '"[0-9]"' "$CONFIG_PATH" 2>/dev/null)
if [ -n "$HAS_CFG" ]; then
    sh "$MODDIR/bin/apply-root.sh" apply >/dev/null 2>&1
fi
