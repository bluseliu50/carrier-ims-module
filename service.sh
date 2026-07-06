#!/system/bin/sh
# service.sh — module late_start service (KernelSU/Magisk/APatch all run this).
# Ensures the config dir + a seed config exist from first boot, then fires a
# boot-safety APPLY_CONFIG broadcast in case BOOT_COMPLETED raced the priv-app.
MODDIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

# First-run seed: an empty disabled config so the priv-app and WebUI have a
# contract from the very first boot.
if [ ! -f "$CONFIG_PATH" ]; then
    echo '{"enabled":false,"applyOnBoot":true,"applyOnSimChange":true,"slots":{}}' > "$CONFIG_PATH"
    chmod 644 "$CONFIG_PATH"
fi

# Boot-safety net: ask the priv-app to apply once it is up. The receiver is
# idempotent (skips when disabled).
(
    sleep 5
    am broadcast -a io.carrierims.action.APPLY_CONFIG --user 0 >/dev/null 2>&1
) &
