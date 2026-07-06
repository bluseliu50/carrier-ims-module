package io.carrierims.applier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Triggered by the WebUI "Apply" button via:
 *   am broadcast -a io.carrierims.action.APPLY_CONFIG
 * Protected by android:permission="android.permission.SHELL" so only the root
 * shell / the module's own scripts can fire it.
 *
 * Runs the apply synchronously in the receiver's foreground execution window
 * (CarrierConfig calls are sub-second). No foreground service is needed — that
 * avoids the startForegroundService-without-startForeground crash.
 */
class ApplyConfigReceiver : BroadcastReceiver() {

    private val tag = "ApplyConfigReceiver"
    val ACTION_APPLY_CONFIG = "io.carrierims.action.APPLY_CONFIG"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_APPLY_CONFIG) return
        Log.i(tag, "APPLY_CONFIG received")
        val config = ConfigStore.read()
        try {
            val outcome = Applier.apply(context.applicationContext, config)
            Log.i(tag, "apply done: ${outcome.slots.size} slot(s)")
        } catch (t: Throwable) {
            Log.e(tag, "apply failed", t)
        }
    }
}
