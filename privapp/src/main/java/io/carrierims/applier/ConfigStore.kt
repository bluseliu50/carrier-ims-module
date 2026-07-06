package io.carrierims.applier

import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Reads the module's single source of truth: /data/adb/carrier_ims/config.json.
 *
 * Schema (see plan "config.json schema"):
 * {
 *   "enabled": true,
 *   "applyOnBoot": true,
 *   "applyOnSimChange": true,
 *   "slots": { "0": { ...SlotConfig fields }, "1": { ... } }
 * }
 *
 * Keyed by slotIndex (stable physical position), NOT subId (unstable across
 *拔卡/换卡). The priv-app maps slotIndex -> active subId at apply time.
 */
object ConfigStore {

    private const val TAG = "ConfigStore"
    const val CONFIG_DIR = "/data/adb/carrier_ims"
    const val CONFIG_PATH = "$CONFIG_DIR/config.json"
    const val STATUS_PATH = "$CONFIG_DIR/status.json"

    data class ModuleConfig(
        val enabled: Boolean,
        val applyOnBoot: Boolean,
        val applyOnSimChange: Boolean,
        val slots: Map<Int, ConfigBuilder.SlotConfig>,
    )

    /** Returns null when the file is missing/unreadable (treated as disabled). */
    fun read(): ModuleConfig? {
        val file = File(CONFIG_PATH)
        val text = runCatching { file.readText() }.getOrNull() ?: return null
        return parse(text)
    }

    fun parse(text: String): ModuleConfig? = try {
        val root = JSONObject(text)
        val slots = mutableMapOf<Int, ConfigBuilder.SlotConfig>()
        val slotsObj = root.optJSONObject("slots")
        if (slotsObj != null) {
            for (key in slotsObj.keys()) {
                val slotIndex = key.toIntOrNull() ?: continue
                val s = slotsObj.optJSONObject(key) ?: continue
                slots[slotIndex] = ConfigBuilder.SlotConfig(
                    carrierName = s.optString("carrierName", ""),
                    countryIso = s.optString("countryIso", ""),
                    countryMccOverride = s.optString("countryMccOverride", ""),
                    volte = s.optBoolean("volte", true),
                    vowifi = s.optBoolean("vowifi", true),
                    vt = s.optBoolean("vt", true),
                    vonr = s.optBoolean("vonr", true),
                    crossSim = s.optBoolean("crossSim", true),
                    ut = s.optBoolean("ut", true),
                    fiveGnr = s.optBoolean("fiveGnr", true),
                    fiveGThresholds = s.optBoolean("fiveGThresholds", true),
                    fiveGPlusIcon = s.optBoolean("fiveGPlusIcon", true),
                    show4gForLte = s.optBoolean("show4gForLte", false),
                )
            }
        }
        ModuleConfig(
            enabled = root.optBoolean("enabled", false),
            applyOnBoot = root.optBoolean("applyOnBoot", true),
            applyOnSimChange = root.optBoolean("applyOnSimChange", true),
            slots = slots,
        )
    } catch (t: Throwable) {
        Log.e(TAG, "parse config.json failed", t)
        null
    }
}
