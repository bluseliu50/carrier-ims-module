#!/system/bin/sh
# customize.sh — KernelSU/Magisk/APatch installer.
# All three roots expose $MODPATH and mount /system overlay + run service.sh,
# so a single zip works everywhere. Root detection is informational only.
SKIPUNZIP=0

ui_print "==================================="
ui_print " Carrier IMS (Root) v1.0.0"
ui_print "==================================="

# --- Detect root manager (informational; all paths share $MODPATH) ---
ROOT_MANAGER="unknown"
if [ "$KSU" = "true" ] || [ -n "$KSU_KERNEL_VER_CODE" ]; then
    ROOT_MANAGER="KernelSU"
elif [ -n "$APATCH" ] || [ -n "$APATCH_VER" ]; then
    ROOT_MANAGER="APatch"
elif [ -n "$MAGISK_VER_CODE" ]; then
    ROOT_MANAGER="Magisk"
fi
ui_print " Root manager: $ROOT_MANAGER"
ui_print " Module path:  $MODPATH"

# --- Verify the priv-app + permissions shipped in the zip ---
APK="$MODPATH/system/priv-app/CarrierImsApplier/CarrierImsApplier.apk"
PERM="$MODPATH/system/etc/permissions/privapp-permissions-carrier_ims.xml"
if [ ! -f "$APK" ]; then
    ui_print "! CarrierImsApplier.apk missing — build the zip with build-module.sh"
    abort "aborting: priv-app apk not found"
fi
if [ ! -f "$PERM" ]; then
    ui_print "! privapp-permissions XML missing"
    abort "aborting: permissions xml not found"
fi
ui_print " Priv-app + permissions present"

# --- Permissions ---
set_perm_recursive "$MODPATH" 0 0 0755 0644
# Ensure scripts are executable.
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/uninstall.sh"    0 0 0755
set_perm_recursive "$MODPATH/bin"   0 0 0755 0755

# webroot perms are auto-fixed by KernelSU (per WebUI doc); Magisk/APatch ignore
# the dir, so leave them alone.

ui_print " Installation complete. Reboot to activate."
ui_print " Open the module WebUI to configure toggles."
