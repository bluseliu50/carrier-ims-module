package io.carrierims.applier

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Triggers an apply pass on BOOT_COMPLETED and on SIM_STATE_CHANGED (LOADED/READY)
 * when the user has enabled auto re-apply. Starting a foreground service from a
 * BOOT_COMPLETED receiver is permitted on modern Android.
 */
class BootReceiver : BroadcastReceiver() {

    private val tag = "BootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(tag, "received $action")
        val config = ConfigStore.read() ?: return
        if (!config.enabled) {
            Log.i(tag, "module disabled; skip")
            return
        }
        when (action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                if (config.applyOnBoot) startApply(context)
            }
            "android.intent.action.SIM_STATE_CHANGED" -> {
                // SIM ready/loaded → apply on SIM change if configured.
                val ss = intent.getStringExtra("ss")
                if (config.applyOnSimChange && (ss == "LOADED" || ss == "READY")) {
                    startApply(context)
                }
            }
            "android.telephony.action.MULTI_SIM_CONFIG_CHANGED" -> {
                if (config.applyOnSimChange) startApply(context)
            }
        }
    }

    private fun startApply(context: Context) {
        val svc = Intent(context, ApplierService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svc)
        } else {
            context.startService(svc)
        }
    }
}
