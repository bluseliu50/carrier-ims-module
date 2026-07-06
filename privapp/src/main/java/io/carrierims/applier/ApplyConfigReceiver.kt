package io.carrierims.applier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Triggered by the WebUI "Apply now" button via:
 *   am broadcast -a io.carrierims.action.APPLY_CONFIG
 * Protected by android:permission="android.permission.SHELL" so only root shell
 * / the module's own scripts can fire it.
 */
class ApplyConfigReceiver : BroadcastReceiver() {

    private val tag = "ApplyConfigReceiver"
    const val ACTION_APPLY_CONFIG = "io.carrierims.action.APPLY_CONFIG"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_APPLY_CONFIG) return
        Log.i(tag, "APPLY_CONFIG received")
        val svc = Intent(context, ApplierService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svc)
        } else {
            context.startService(svc)
        }
    }
}
