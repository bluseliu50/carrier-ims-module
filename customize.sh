#!/system/bin/sh
# customize.sh — KernelSU/Magisk/APatch installer.
# Pure-root mode: no priv-app, no /system overlay. The applier runs via
# app_process as uid 0. Zero boot-loop risk.
SKIPUNZIP=0

ui_print "==================================="
ui_print " Carrier IMS (Root) v1.0.0"
ui_print "==================================="

ROOT_MANAGER="unknown"
if [ "$KSU" = "true" ] || [ -n "$KSU_KERNEL_VER_CODE" ]; then
    ROOT_MANAGER="KernelSU"
elif [ -n "$APATCH" ] || [ -n "$APATCH_VER" ]; then
    ROOT_MANAGER="APatch"
elif [ -n "$MAGISK_VER_CODE" ]; then
    ROOT_MANAGER="Magisk"
fi
ui_print " Root manager: $ROOT_MANAGER"
ui_print " Mode: pure-root (app_process, no priv-app)"

# Verify the applier dex shipped in the zip.
DEX="$MODPATH/system/bin/Applier.dex"
if [ ! -f "$DEX" ]; then
    ui_print "! Applier.dex missing — rebuild with build-module.sh"
    abort "aborting: applier dex not found"
fi
ui_print " Applier dex present"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/uninstall.sh"    0 0 0755
set_perm_recursive "$MODPATH/bin"   0 0 0755 0755

ui_print " Installation complete. Reboot to activate."
ui_print " Open the module WebUI to configure toggles."
