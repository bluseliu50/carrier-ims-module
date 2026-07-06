package io.carrierims.applier

import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.telephony.CarrierConfigManager
import android.util.Log

/**
 * Builds the CarrierConfig override [PersistableBundle] for a single SIM slot.
 *
 * Ported from the original Shizuku app's ImsModifier.buildBundle so the
 * boolean toggles behave identically to the non-root app. Manual carrier-name
 * / country-ISO / MCC inputs were removed; the "TikTok fix" toggle auto-applies
 * a CN country-ISO + MCC override (the mechanism the original used).
 */
object ConfigBuilder {

    private const val TAG = "ConfigBuilder"

    private const val KEY_NR_ADVANCED_THRESHOLD_BANDWIDTH_KHZ =
        "nr_advanced_threshold_bandwidth_khz_int"
    private const val KEY_ADDITIONAL_NR_ADVANCED_BANDS = "additional_nr_advanced_bands_int_array"
    private const val KEY_5G_ICON_CONFIGURATION = "5g_icon_configuration_string"
    private const val KEY_NR_ADVANCED_CAPABLE_PCO_ID = "nr_advanced_capable_pco_id_int"
    private const val KEY_INCLUDE_LTE_FOR_NR_ADVANCED_THRESHOLD_BANDWIDTH =
        "include_lte_for_nr_advanced_threshold_bandwidth_bool"
    private const val NR_ADVANCED_THRESHOLD_KHZ_FOR_5GA = 110_000
    private const val NR_ICON_CONFIGURATION_5GA =
        "connected_mmwave:5G_Plus,connected:5G,connected_rrc_idle:5G,not_restricted_rrc_idle:5G,not_restricted_rrc_con:5G"

    // CarrierConfig key for the MCC override used by the TikTok fix.
    private const val BUNDLE_COUNTRY_MCC_OVERRIDE = "country_mcc_override"
    private const val TIKTOK_FIX_MCC = "460"

    private val NR_ADVANCED_BANDS_FOR_CHINA = intArrayOf(1, 3, 8, 28, 41, 78, 79)

    /**
     * Per-slot configuration. Defaults mirror app/.../model/Feature.kt.
     */
    data class SlotConfig(
        val volte: Boolean = true,
        val vowifi: Boolean = true,
        val vt: Boolean = true,
        val vonr: Boolean = true,
        val crossSim: Boolean = true,
        val ut: Boolean = true,
        val fiveGnr: Boolean = true,
        val fiveGThresholds: Boolean = true,
        val fiveGPlusIcon: Boolean = true,
        val show4gForLte: Boolean = false,
        val tiktokNetworkFix: Boolean = false,
    )

    fun build(slot: SlotConfig): PersistableBundle {
        val bundle = Bundle()

        // TikTok 修复: auto-apply a CN country-ISO + MCC override so region
        // detection (the original "tiktok network fix") works without a manual
        // country-code field.
        if (slot.tiktokNetworkFix) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                bundle.putString(
                    CarrierConfigManager.KEY_SIM_COUNTRY_ISO_OVERRIDE_STRING,
                    "cn",
                )
            }
            bundle.putString(BUNDLE_COUNTRY_MCC_OVERRIDE, TIKTOK_FIX_MCC)
        }

        // VoLTE
        if (slot.volte) {
            bundle.putBoolean(CarrierConfigManager.KEY_CARRIER_VOLTE_AVAILABLE_BOOL, true)
            bundle.putBoolean(CarrierConfigManager.KEY_EDITABLE_ENHANCED_4G_LTE_BOOL, true)
            bundle.putBoolean(CarrierConfigManager.KEY_HIDE_ENHANCED_4G_LTE_BOOL, false)
            bundle.putBoolean(CarrierConfigManager.KEY_HIDE_LTE_PLUS_DATA_ICON_BOOL, false)
        }
        // LTE 显示为 4G
        if (slot.show4gForLte) {
            bundle.putBoolean("show_4g_for_lte_data_icon_bool", true)
        }
        // VT (视频通话)
        if (slot.vt) {
            bundle.putBoolean(CarrierConfigManager.KEY_CARRIER_VT_AVAILABLE_BOOL, true)
        }
        // UT 补充服务
        if (slot.ut) {
            bundle.putBoolean(CarrierConfigManager.KEY_CARRIER_SUPPORTS_SS_OVER_UT_BOOL, true)
        }
        // 跨 SIM 通话
        if (slot.crossSim) {
            bundle.putBoolean(CarrierConfigManager.KEY_CARRIER_CROSS_SIM_IMS_AVAILABLE_BOOL, true)
            bundle.putBoolean(
                CarrierConfigManager.KEY_ENABLE_CROSS_SIM_CALLING_ON_OPPORTUNISTIC_DATA_BOOL,
                true,
            )
        }
        // VoWiFi
        if (slot.vowifi) {
            bundle.putBoolean(CarrierConfigManager.KEY_CARRIER_WFC_IMS_AVAILABLE_BOOL, true)
            bundle.putBoolean(CarrierConfigManager.KEY_CARRIER_WFC_SUPPORTS_WIFI_ONLY_BOOL, true)
            bundle.putBoolean(CarrierConfigManager.KEY_EDITABLE_WFC_MODE_BOOL, true)
            bundle.putBoolean(CarrierConfigManager.KEY_EDITABLE_WFC_ROAMING_MODE_BOOL, true)
            bundle.putBoolean("show_wifi_calling_icon_in_status_bar_bool", true)
            bundle.putInt("wfc_spn_format_idx_int", 6)
        }
        // VoNR (5G 语音)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (slot.vonr) {
                bundle.putBoolean(CarrierConfigManager.KEY_VONR_ENABLED_BOOL, true)
                bundle.putBoolean(CarrierConfigManager.KEY_VONR_SETTING_VISIBILITY_BOOL, true)
            }
        }
        // 5G NR
        if (slot.fiveGnr) {
            bundle.putIntArray(
                CarrierConfigManager.KEY_CARRIER_NR_AVAILABILITIES_INT_ARRAY,
                intArrayOf(
                    CarrierConfigManager.CARRIER_NR_AVAILABILITY_NSA,
                    CarrierConfigManager.CARRIER_NR_AVAILABILITY_SA,
                ),
            )
            if (slot.fiveGPlusIcon) {
                bundle.putInt(KEY_NR_ADVANCED_THRESHOLD_BANDWIDTH_KHZ, NR_ADVANCED_THRESHOLD_KHZ_FOR_5GA)
                bundle.putBoolean(KEY_INCLUDE_LTE_FOR_NR_ADVANCED_THRESHOLD_BANDWIDTH, false)
                bundle.putIntArray(KEY_ADDITIONAL_NR_ADVANCED_BANDS, NR_ADVANCED_BANDS_FOR_CHINA)
                bundle.putString(KEY_5G_ICON_CONFIGURATION, NR_ICON_CONFIGURATION_5GA)
                bundle.putInt(KEY_NR_ADVANCED_CAPABLE_PCO_ID, 0)
            }
            if (slot.fiveGThresholds) {
                bundle.putIntArray(
                    CarrierConfigManager.KEY_5G_NR_SSRSRP_THRESHOLDS_INT_ARRAY,
                    intArrayOf(-128, -118, -108, -98),
                )
            }
        }
        return bundle.toPersistableBundle()
    }

    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    private fun Bundle.toPersistableBundle(): PersistableBundle {
        val pb = PersistableBundle()
        for (key in this.keySet()) {
            val value = this.get(key)
            when (value) {
                is Int -> pb.putInt(key, value)
                is Long -> pb.putLong(key, value)
                is Double -> pb.putDouble(key, value)
                is String -> pb.putString(key, value)
                is Boolean -> pb.putBoolean(key, value)
                is IntArray -> pb.putIntArray(key, value)
                is LongArray -> pb.putLongArray(key, value)
                is DoubleArray -> pb.putDoubleArray(key, value)
                is BooleanArray -> pb.putBooleanArray(key, value)
                else -> {
                    if (value is Array<*> && value.isArrayOf<String>()) {
                        pb.putStringArray(key, value as Array<String>)
                    } else {
                        Log.i(TAG, "toPersistableBundle: unsupported type for key $key")
                    }
                }
            }
        }
        return pb
    }
}
