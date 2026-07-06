#!/system/bin/sh
# bin/read-config.sh — WebUI reads the current config.json for prefill.
CONFIG_PATH=/data/adb/carrier_ims/config.json
if [ -f "$CONFIG_PATH" ]; then
    cat "$CONFIG_PATH"
else
    echo '{"slots":{}}'
fi
