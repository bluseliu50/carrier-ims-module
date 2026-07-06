#!/system/bin/sh
# bin/cc-apply.sh — translates config.json into `cmd phone cc set-value -p` calls.
#
# Suppresses ALL non-JSON output. The only stdout line is the final JSON result.
# Usage: sh cc-apply.sh <config.json> <status.json>
CONFIG_PATH="${1:-/data/adb/carrier_ims/config.json}"
STATUS_PATH="${2:-/data/adb/carrier_ims/status.json}"

# Suppress all stderr for the entire script.
exec 2>/dev/null

# Check if cmd phone cc is available.
if ! command -v cmd >/dev/null 2>&1; then
    NOW=$(date +%s)000
    echo "{\"lastApplyMillis\":$NOW,\"applied\":false,\"error\":\"cmd not found\"}" > "$STATUS_PATH"
    echo '{"ok":false,"error":"cmd not found in PATH"}'
    exit 1
fi

# Quick availability test.
cmd phone cc set-value -p test_availability_bool false >/dev/null 2>&1
CC_RC=$?
if [ "$CC_RC" -ne 0 ]; then
    NOW=$(date +%s)000
    echo "{\"lastApplyMillis\":$NOW,\"applied\":false,\"error\":\"cmd phone cc failed (exit $CC_RC)\"}" > "$STATUS_PATH"
    echo "{\"ok\":false,\"error\":\"cmd phone cc exit $CC_RC\"}"
    exit 1
fi

set_bool() {
    cmd phone cc set-value -p "$1" "$2" >/dev/null 2>&1
}
set_str() {
    cmd phone cc set-value -p "$1" "$2" >/dev/null 2>&1
}
set_int() {
    cmd phone cc set-value -p "$1" "$2" >/dev/null 2>&1
}
set_int_array() {
    cmd phone cc set-value -p "$1" "$2" >/dev/null 2>&1
}

get_bool() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*\(true\|false\)" "$CONFIG_PATH" 2>/dev/null | head -1 | grep -oE '(true|false)$'
}

APPLIED=0
ERRCOUNT=0

apply_slot() {
    VOLTE=$(get_bool "volte")
    [ -z "$VOLTE" ] && return

    VOWIFI=$(get_bool "vowifi")
    VT=$(get_bool "vt")
    VONR=$(get_bool "vonr")
    CROSS=$(get_bool "crossSim")
    UT=$(get_bool "ut")
    FIVE_NR=$(get_bool "fiveGnr")
    FIVE_PLUS=$(get_bool "fiveGPlusIcon")
    FIVE_THR=$(get_bool "fiveGThresholds")
    SHOW4G=$(get_bool "show4gForLte")
    TIKTOK=$(get_bool "tiktokNetworkFix")

    [ "$VOLTE" = "true" ] && { set_bool carrier_volte_available_bool true || ERRCOUNT=$((ERRCOUNT+1)); set_bool editable_enhanced_4g_lte_bool true; set_bool hide_enhanced_4g_lte_bool false; set_bool hide_lte_plus_data_icon_bool false; }
    [ "$SHOW4G" = "true" ] && set_bool show_4g_for_lte_data_icon_bool true
    [ "$VT" = "true" ] && set_bool carrier_vt_available_bool true
    [ "$UT" = "true" ] && set_bool carrier_supports_ss_over_ut_bool true
    [ "$CROSS" = "true" ] && { set_bool carrier_cross_sim_ims_available_bool true; set_bool enable_cross_sim_calling_on_opportunistic_data_bool true; }
    [ "$VOWIFI" = "true" ] && { set_bool carrier_wfc_ims_available_bool true; set_bool carrier_wfc_supports_wifi_only_bool true; set_bool editable_wfc_mode_bool true; set_bool editable_wfc_roaming_mode_bool true; set_bool show_wifi_calling_icon_in_status_bar_bool true; set_int wfc_spn_format_idx_int 6; }
    [ "$VONR" = "true" ] && { set_bool vonr_enabled_bool true; set_bool vonr_setting_visibility_bool true; }
    if [ "$FIVE_NR" = "true" ]; then
        set_int_array carrier_nr_availabilities_int_array "1 2"
        [ "$FIVE_PLUS" = "true" ] && {
            set_int nr_advanced_threshold_bandwidth_khz_int 110000
            set_bool include_lte_for_nr_advanced_threshold_bandwidth_bool false
            set_int_array additional_nr_advanced_bands_int_array "1 3 8 28 41 78 79"
            set_str 5g_icon_configuration_string "connected_mmwave:5G_Plus,connected:5G,connected_rrc_idle:5G,not_restricted_rrc_idle:5G,not_restricted_rrc_con:5G"
            set_int nr_advanced_capable_pco_id_int 0
        }
        [ "$FIVE_THR" = "true" ] && set_int_array 5g_nr_ssrsrp_thresholds_int_array "-128 -118 -108 -98"
    fi
    [ "$TIKTOK" = "true" ] && { set_str sim_country_iso_override_string "cn"; set_str country_mcc_override "460"; }

    APPLIED=$((APPLIED + 1))
}

apply_slot 0
apply_slot 1

NOW=$(date +%s)000
if [ "$APPLIED" -gt 0 ]; then
    echo "{\"lastApplyMillis\":$NOW,\"applied\":true,\"slots\":[{\"slotIndex\":0,\"applied\":true,\"errors\":$ERRCOUNT}]}" > "$STATUS_PATH"
    echo '{"ok":true}'
else
    echo "{\"lastApplyMillis\":$NOW,\"applied\":false,\"error\":\"no slot config\"}" > "$STATUS_PATH"
    echo '{"ok":false,"error":"no slot config"}'
fi
