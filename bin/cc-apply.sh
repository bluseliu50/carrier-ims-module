#!/system/bin/sh
# bin/cc-apply.sh — translates config.json into `cmd phone cc set-value -p` calls.
#
# `cmd phone cc set-value -p <key> <value>` is a built-in Android command that
# persistently overrides a carrier config key. Root shell can run it directly.
# This script reads config.json (keyed by slot index) and applies overrides
# for all active SIMs.
#
# Usage: sh cc-apply.sh <config.json> <status.json>
CONFIG_PATH="${1:-/data/adb/carrier_ims/config.json}"
STATUS_PATH="${2:-/data/adb/carrier_ims/status.json}"

# Helper: set a boolean carrier config override (persistent).
set_bool() {
    cmd phone cc set-value -p "$1" "$2" >/dev/null 2>&1
}

# Helper: set a string carrier config override.
set_str() {
    cmd phone cc set-value -p "$1" "$2" >/dev/null 2>&1
}

# Helper: set an int carrier config override.
set_int() {
    cmd phone cc set-value -p "$1" "$2" >/dev/null 2>&1
}

# Helper: set an int-array carrier config override (space-separated).
# cmd phone cc set-value -p <key> "<v1> <v2> ..."
set_int_array() {
    cmd phone cc set-value -p "$1" "$2" >/dev/null 2>&1
}

# We don't know which slot maps to which subId from shell easily, but
# `cmd phone cc` applies to the default subscription. For multi-SIM,
# we apply the same config to all slots by iterating subIds.
# Get list of active subscription IDs.
get_sub_ids() {
    # `cmd phone cc` applies to the current default data sub by default.
    # For per-slot control we'd need -s <subId>, which may not be supported
    # on all Android versions. For now apply to default (covers single-SIM
    # and dual-SIM where both slots use the same config).
    echo ""
}

APPLIED=0
ERRORS=""

# Parse config.json with a simple approach: check each key with grep.
# config.json format: {"slots":{"0":{"volte":true,"vowifi":true,...}}}
# We apply slot 0's config (most common single-SIM case). For dual-SIM
# users, slot 1 overrides are also applied after slot 0.

apply_slot() {
    SLOT="$1"
    PREFIX=".slots.\"$SLOT\""

    # Extract boolean values using grep/sed (no jq dependency)
    get_bool() {
        # $1 = key name
        grep -o "\"$1\"[[:space:]]*:[[:space:]]*\(true\|false\)" "$CONFIG_PATH" | head -1 | grep -oE '(true|false)$'
    }

    VOLTE=$(get_bool "volte")
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

    # If this slot has no config (grep found nothing for volte), skip.
    if [ -z "$VOLTE" ]; then
        return
    fi

    # VoLTE
    if [ "$VOLTE" = "true" ]; then
        set_bool carrier_volte_available_bool true
        set_bool editable_enhanced_4g_lte_bool true
        set_bool hide_enhanced_4g_lte_bool false
        set_bool hide_lte_plus_data_icon_bool false
    fi

    # LTE show as 4G
    if [ "$SHOW4G" = "true" ]; then
        set_bool show_4g_for_lte_data_icon_bool true
    fi

    # VT
    if [ "$VT" = "true" ]; then
        set_bool carrier_vt_available_bool true
    fi

    # UT
    if [ "$UT" = "true" ]; then
        set_bool carrier_supports_ss_over_ut_bool true
    fi

    # Cross-SIM
    if [ "$CROSS" = "true" ]; then
        set_bool carrier_cross_sim_ims_available_bool true
        set_bool enable_cross_sim_calling_on_opportunistic_data_bool true
    fi

    # VoWiFi
    if [ "$VOWIFI" = "true" ]; then
        set_bool carrier_wfc_ims_available_bool true
        set_bool carrier_wfc_supports_wifi_only_bool true
        set_bool editable_wfc_mode_bool true
        set_bool editable_wfc_roaming_mode_bool true
        set_bool show_wifi_calling_icon_in_status_bar_bool true
        set_int wfc_spn_format_idx_int 6
    fi

    # VoNR
    if [ "$VONR" = "true" ]; then
        set_bool vonr_enabled_bool true
        set_bool vonr_setting_visibility_bool true
    fi

    # 5G NR
    if [ "$FIVE_NR" = "true" ]; then
        set_int_array carrier_nr_availabilities_int_array "1 2"

        if [ "$FIVE_PLUS" = "true" ]; then
            set_int nr_advanced_threshold_bandwidth_khz_int 110000
            set_bool include_lte_for_nr_advanced_threshold_bandwidth_bool false
            set_int_array additional_nr_advanced_bands_int_array "1 3 8 28 41 78 79"
            set_str 5g_icon_configuration_string "connected_mmwave:5G_Plus,connected:5G,connected_rrc_idle:5G,not_restricted_rrc_idle:5G,not_restricted_rrc_con:5G"
            set_int nr_advanced_capable_pco_id_int 0
        fi

        if [ "$FIVE_THR" = "true" ]; then
            set_int_array 5g_nr_ssrsrp_thresholds_int_array "-128 -118 -108 -98"
        fi
    fi

    # TikTok fix
    if [ "$TIKTOK" = "true" ]; then
        set_str sim_country_iso_override_string "cn"
        set_str country_mcc_override "460"
    fi

    APPLIED=$((APPLIED + 1))
}

# Apply slot 0 and slot 1
apply_slot 0
apply_slot 1

# Write status.json
NOW=$(date +%s)000
if [ "$APPLIED" -gt 0 ]; then
    echo "{\"lastApplyMillis\":$NOW,\"applied\":true,\"slots\":[{\"slotIndex\":0,\"applied\":true}]}" > "$STATUS_PATH"
    echo '{"ok":true}'
else
    echo "{\"lastApplyMillis\":$NOW,\"applied\":false,\"error\":\"no slot config found\"}" > "$STATUS_PATH"
    echo '{"ok":false,"error":"no slot config found"}'
fi
