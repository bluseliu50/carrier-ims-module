package io.carrierims.applier

import android.content.Context
import android.os.PersistableBundle
import android.telephony.CarrierConfigManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Applies CarrierConfig overrides for every active subscription whose
 * slotIndex is present in [ConfigStore.ModuleConfig.slots].
 *
 * Persistence strategy (solves "每次启动重新执行"):
 *  - Primary: overrideConfig(subId, bundle, persistent=true). This succeeds
 *    because the app is installed under /system/priv-app/ (→ FLAG_SYSTEM) and
 *    holds MODIFY_PHONE_STATE (signature|privileged) via the privapp-permissions
 *    XML — the exact gate that ShizukuProvider.kt:168 enforces.
 *  - Contingency: if a ROM still rejects persistent, fall back to non-persistent
 *    overrideConfig; the boot + SIM-change auto re-apply covers the gap.
 */
object Applier {

    private const val TAG = "Applier"

    data class SlotResult(
        val slotIndex: Int,
        val subId: Int,
        val applied: Boolean,
        val imsRegistered: Boolean,
        val error: String? = null,
    )

    data class ApplyOutcome(
        val lastApplyMillis: Long,
        val enabled: Boolean,
        val slots: List<SlotResult>,
    )

    fun apply(context: Context, config: ConfigStore.ModuleConfig): ApplyOutcome {
        val results = mutableListOf<SlotResult>()
        val now = System.currentTimeMillis()

        if (!config.enabled) {
            writeStatus(now, enabled = false, emptyList())
            return ApplyOutcome(now, enabled = false, slots = emptyList())
        }

        val cm = context.getSystemService(CarrierConfigManager::class.java)
        val sm = context.getSystemService(SubscriptionManager::class.java)
        val tm = context.getSystemService(TelephonyManager::class.java)

        val activeSubs: List<SubscriptionInfo> = try {
            @Suppress("DEPRECATION")
            sm?.activeSubscriptionInfoList ?: emptyList()
        } catch (t: Throwable) {
            Log.e(TAG, "getActiveSubscriptionInfoList failed", t)
            emptyList()
        }

        if (cm == null || sm == null || tm == null) {
            results.add(
                SlotResult(
                    slotIndex = -1,
                    subId = -1,
                    applied = false,
                    imsRegistered = false,
                    error = "system service unavailable",
                ),
            )
            writeStatus(now, enabled = true, results)
            return ApplyOutcome(now, enabled = true, slots = results)
        }

        for (sub in activeSubs) {
            val slotIndex = sub.simSlotIndex
            val subId = sub.subscriptionId
            val slotConfig = config.slots[slotIndex]
            if (slotConfig == null) {
                Log.i(TAG, "no config for slot $slotIndex (subId $subId), skip")
                continue
            }
            val bundle = ConfigBuilder.build(slotConfig)
            val applied = try {
                invokeOverrideConfig(cm, subId, bundle, persistent = true)
                Log.i(TAG, "overrideConfig persistent success for subId $subId (slot $slotIndex)")
                true
            } catch (persistentError: Throwable) {
                Log.w(TAG, "persistent failed for subId $subId, fallback non-persistent", persistentError)
                try {
                    invokeOverrideConfig(cm, subId, bundle, persistent = false)
                    Log.i(TAG, "fallback non-persistent success for subId $subId")
                    true
                } catch (fallbackError: Throwable) {
                    fallbackError.addSuppressed(persistentError)
                    Log.e(TAG, "overrideConfig failed for subId $subId", fallbackError)
                    false
                }
            }

            val imsRegistered = try {
                // createForSubscriptionId(int) and isImsRegistered(int) are
                // hidden @SystemApi; reflect to compile against the public SDK.
                val perSubTm = TelephonyManager::class.java
                    .getMethod("createForSubscriptionId", Int::class.javaPrimitiveType)
                    .invoke(tm, subId) as? TelephonyManager
                perSubTm?.let {
                    TelephonyManager::class.java
                        .getMethod("isImsRegistered", Int::class.javaPrimitiveType)
                        .invoke(it, subId) as? Boolean
                } ?: false
            } catch (t: Throwable) {
                Log.w(TAG, "isImsRegistered read failed for subId $subId", t)
                false
            }

            results.add(
                SlotResult(
                    slotIndex = slotIndex,
                    subId = subId,
                    applied = applied,
                    imsRegistered = imsRegistered,
                    error = if (applied) null else "overrideConfig rejected",
                ),
            )
        }

        writeStatus(now, enabled = true, results)
        return ApplyOutcome(now, enabled = true, slots = results)
    }

    /** Reflective overrideConfig: try 3-arg (subId, bundle, persistent) then 2-arg. */
    private fun invokeOverrideConfig(
        cm: CarrierConfigManager,
        subId: Int,
        values: PersistableBundle?,
        persistent: Boolean,
    ) {
        try {
            cm.javaClass.getMethod(
                "overrideConfig",
                Int::class.javaPrimitiveType,
                PersistableBundle::class.java,
                Boolean::class.javaPrimitiveType,
            ).invoke(cm, subId, values, persistent)
        } catch (_: NoSuchMethodException) {
            cm.javaClass.getMethod(
                "overrideConfig",
                Int::class.javaPrimitiveType,
                PersistableBundle::class.java,
            ).invoke(cm, subId, values)
        }
    }

    private fun writeStatus(now: Long, enabled: Boolean, slots: List<SlotResult>) {
        try {
            val arr = JSONArray()
            for (s in slots) {
                arr.put(
                    JSONObject()
                        .put("slotIndex", s.slotIndex)
                        .put("subId", s.subId)
                        .put("applied", s.applied)
                        .put("imsRegistered", s.imsRegistered)
                        .also { o -> s.error?.let { o.put("error", it) } },
                )
            }
            val status = JSONObject()
                .put("lastApplyMillis", now)
                .put("enabled", enabled)
                .put("slots", arr)
            File(ConfigStore.CONFIG_DIR).mkdirs()
            File(ConfigStore.STATUS_PATH).writeText(status.toString())
            Log.i(TAG, "status.json written")
        } catch (t: Throwable) {
            Log.e(TAG, "write status.json failed", t)
        }
    }
}
