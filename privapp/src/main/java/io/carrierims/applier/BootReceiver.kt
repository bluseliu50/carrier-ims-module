package io.carrierims.applier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-applies config on BOOT_COMPLETED and on SIM_STATE_CHANGED (LOADED/READY),
 * and on MULTI_SIM_CONFIG_CHANGED. Boot + SIM-change re-apply is always on;
 * there is no per-user toggle (disabling the module is the root manager's job).
 *
 * Applies synchronously in the receiver's foreground execution window — no
 * foreground service (avoids the startForegroundService-without-startForeground
 * crash).
 */
class BootReceiver : BroadcastReceiver() {

    private val tag = "BootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(tag, "received $action")
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.SIM_STATE_CHANGED",
            "android.telephony.action.MULTI_SIM_CONFIG_CHANGED",
            "android.telephony.action.CARRIER_CONFIG_CHANGED",
            -> applyNow(context)
        }
    }

    private fun applyNow(context: Context) {
        val config = ConfigStore.read()
        if (config.slots.isEmpty()) {
            Log.i(tag, "no slot config; skip")
            return
        }
        try {
            val outcome = Applier.apply(context.applicationContext, config)
            Log.i(tag, "apply done: ${outcome.slots.size} slot(s)")
        } catch (t: Throwable) {
            Log.e(tag, "apply failed", t)
        }
    }
}
