#!/system/bin/sh
# bin/apply.sh — decode base64 config + apply CarrierConfig overrides via cmd phone cc.
#
# This is the SOLE entry point from the WebUI. It outputs exactly ONE JSON line
# on stdout (parsed by app.js). All diagnostics go to a log file the user can cat.
#
# Usage: sh apply.sh <base64-config-json>
SCRIPT_DIR=${0%/*}
CONFIG_DIR=/data/adb/carrier_ims
CONFIG_PATH="$CONFIG_DIR/config.json"
STATUS_PATH="$CONFIG_DIR/status.json"
LOG_PATH="$CONFIG_DIR/apply.log"

mkdir -p "$CONFIG_DIR"

# Everything diagnostic goes to the log, NEVER to stdout (app.js reads stdout).
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_PATH"; }

emit() { echo "$1"; log "RESULT: $1"; }

log "=== apply invoked ==="

# ---- decode config ----
if [ -z "$1" ]; then
    emit '{"ok":false,"error":"无输入参数"}'
    exit 1
fi

if command -v base64 >/dev/null 2>&1; then
    printf '%s' "$1" | base64 -d > "$CONFIG_PATH" 2>>"$LOG_PATH"
else
    printf '%s' "$1" | toybox base64 -d > "$CONFIG_PATH" 2>>"$LOG_PATH"
fi
if [ ! -s "$CONFIG_PATH" ]; then
    emit '{"ok":false,"error":"base64 解码失败"}'
    exit 1
fi
chmod 644 "$CONFIG_PATH"
log "config decoded: $(cat "$CONFIG_PATH")"

# ---- find a working cmd phone cc invocation ----
# Root (uid 0) gets "cc: Permission denied" on some ROMs. The shell user
# (uid 2000) is the identity that the phone service trusts for cc overrides
# (same identity Shizuku uses). Try root first, then shell uid.
CC=""
if cmd phone cc set-value -p __probe_bool false >>"$LOG_PATH" 2>&1; then
    CC="cmd phone cc"
    log "cc works as: root"
elif su 2000 -c 'cmd phone cc set-value -p __probe_bool false' >>"$LOG_PATH" 2>&1; then
    CC="su 2000 -c cmd phone cc"
    log "cc works as: shell(2000)"
else
    log "cc probe FAILED both methods. Trying service list..."
    service list >>"$LOG_PATH" 2>&1
    emit '{"ok":false,"error":"cmd phone cc 权限被拒（root 和 shell 均失败），请查看 apply.log"}'
    exit 1
fi

# ---- helpers ----
setval() {
    # $1=key $2=value ; CC is space-split into command + args
    $CC set-value -p "$1" "$2" >>"$LOG_PATH" 2>&1
}

get_bool() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*\(true\|false\)" "$CONFIG_PATH" 2>/dev/null | head -1 | grep -oE '(true|false)$'
}

# ---- apply per slot ----
APPLIED=0

apply_slot() {
    V=$(get_bool volte); [ -z "$V" ] && { log "slot $1: no config, skip"; return; }
    log "slot $1: applying"

    VOWIFI=$(get_bool vowifi); VT=$(get_bool vt); VONR=$(get_bool vonr)
    CROSS=$(get_bool crossSim); UT=$(get_bool ut)
    FIVENR=$(get_bool fiveGnr); FIVEPLUS=$(get_bool fiveGPlusIcon)
    FIVETHR=$(get_bool fiveGThresholds); SHOW4G=$(get_bool show4gForLte)
    TIKTOK=$(get_bool tiktokNetworkFix)

    [ "$V" = "true" ] && {
        setval carrier_volte_available_bool true
        setval editable_enhanced_4g_lte_bool true
        setval hide_enhanced_4g_lte_bool false
        setval hide_lte_plus_data_icon_bool false
    }
    [ "$SHOW4G" = "true" ] && setval show_4g_for_lte_data_icon_bool true
    [ "$VT" = "true" ] && setval carrier_vt_available_bool true
    [ "$UT" = "true" ] && setval carrier_supports_ss_over_ut_bool true
    [ "$CROSS" = "true" ] && {
        setval carrier_cross_sim_ims_available_bool true
        setval enable_cross_sim_calling_on_opportunistic_data_bool true
    }
    [ "$VOWIFI" = "true" ] && {
        setval carrier_wfc_ims_available_bool true
        setval carrier_wfc_supports_wifi_only_bool true
        setval editable_wfc_mode_bool true
        setval editable_wfc_roaming_mode_bool true
        setval show_wifi_calling_icon_in_status_bar_bool true
        setval wfc_spn_format_idx_int 6
    }
    [ "$VONR" = "true" ] && {
        setval vonr_enabled_bool true
        setval vonr_setting_visibility_bool true
    }
    [ "$FIVENR" = "true" ] && {
        setval carrier_nr_availabilities_int_array "1 2"
        [ "$FIVEPLUS" = "true" ] && {
            setval nr_advanced_threshold_bandwidth_khz_int 110000
            setval include_lte_for_nr_advanced_threshold_bandwidth_bool false
            setval additional_nr_advanced_bands_int_array "1 3 8 28 41 78 79"
            setval 5g_icon_configuration_string "connected_mmwave:5G_Plus,connected:5G,connected_rrc_idle:5G,not_restricted_rrc_idle:5G,not_restricted_rrc_con:5G"
            setval nr_advanced_capable_pco_id_int 0
        }
        [ "$FIVETHR" = "true" ] && setval 5g_nr_ssrsrp_thresholds_int_array "-128 -118 -108 -98"
    }
    [ "$TIKTOK" = "true" ] && {
        setval sim_country_iso_override_string "cn"
        setval country_mcc_override "460"
    }
    APPLIED=$((APPLIED + 1))
}

apply_slot 0
apply_slot 1

NOW=$(date +%s)000
if [ "$APPLIED" -gt 0 ]; then
    echo "{\"lastApplyMillis\":$NOW,\"applied\":true,\"slots\":[{\"slotIndex\":0,\"applied\":true}]}" > "$STATUS_PATH"
    emit '{"ok":true}'
else
    echo "{\"lastApplyMillis\":$NOW,\"applied\":false,\"error\":\"未找到卡槽配置\"}" > "$STATUS_PATH"
    emit '{"ok":false,"error":"未找到卡槽配置"}'
fi
