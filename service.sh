#!/system/bin/sh
# service.sh — module late_start service.
# Seeds config.json on first run, then applies CarrierConfig via cmd phone cc.
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
    # apply.sh reads config.json itself; pass an empty arg-free form by
    # invoking it with the config already on disk. Re-encode is unnecessary —
    # call apply.sh in "from-file" mode by giving it the raw file via a noop.
    B64=$(cat "$CONFIG_PATH" | base64 | tr -d '\n')
    sh "$MODDIR/bin/apply.sh" "$B64" >/dev/null 2>&1
fi
