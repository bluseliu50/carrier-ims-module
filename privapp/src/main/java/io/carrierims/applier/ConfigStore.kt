package io.carrierims.applier

import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Reads the module's single source of truth: /data/adb/carrier_ims/config.json.
 *
 * Schema (see AGENTS.md). Keyed by slotIndex (stable physical positions), not
 * subId (unstable across拔卡/换卡). The priv-app maps slotIndex -> active
 * subId at apply time.
 *
 * There is no master "enabled" flag: enabling/disabling the whole module is the
 * root manager's job (module toggle). Boot + SIM-change auto re-apply are
 * always on.
 */
object ConfigStore {

    private const val TAG = "ConfigStore"
    const val CONFIG_DIR = "/data/adb/carrier_ims"
    const val CONFIG_PATH = "$CONFIG_DIR/config.json"
    const val STATUS_PATH = "$CONFIG_DIR/status.json"

    data class ModuleConfig(
        val slots: Map<Int, ConfigBuilder.SlotConfig>,
    )

    /** Returns an empty config (no slots) when the file is missing/unreadable. */
    fun read(): ModuleConfig {
        val file = File(CONFIG_PATH)
        val text = runCatching { file.readText() }.getOrNull()
            ?: return ModuleConfig(slots = emptyMap())
        return parse(text)
    }

    fun parse(text: String): ModuleConfig = try {
        val root = JSONObject(text)
        val slots = mutableMapOf<Int, ConfigBuilder.SlotConfig>()
        val slotsObj = root.optJSONObject("slots")
        if (slotsObj != null) {
            for (key in slotsObj.keys()) {
                val slotIndex = key.toIntOrNull() ?: continue
                val s = slotsObj.optJSONObject(key) ?: continue
                slots[slotIndex] = ConfigBuilder.SlotConfig(
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
                    tiktokNetworkFix = s.optBoolean("tiktokNetworkFix", false),
                )
            }
        }
        ModuleConfig(slots = slots)
    } catch (t: Throwable) {
        Log.e(TAG, "parse config.json failed", t)
        ModuleConfig(slots = emptyMap())
    }
}
