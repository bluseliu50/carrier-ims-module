#!/system/bin/sh
# bin/status.sh — WebUI reads the last apply result.
STATUS_PATH=/data/adb/carrier_ims/status.json
if [ -f "$STATUS_PATH" ]; then
    cat "$STATUS_PATH"
else
    echo '{}'
fi
