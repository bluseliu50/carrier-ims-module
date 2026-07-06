package io.carrierims.applier

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log

/**
 * Foreground service that runs a single apply pass and (optionally) holds a
 * TelephonyCallback so SIM/sub changes trigger a re-apply when configured.
 *
 * Started by BootReceiver (BOOT_COMPLETED / SIM_STATE_CHANGED) and
 * ApplyConfigReceiver (WebUI "Apply now").
 */
class ApplierService : Service() {

    private val tag = "ApplierService"
    private var callback: ActiveSubCallback? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val config = ConfigStore.read()
        if (config == null || !config.enabled) {
            Log.i(tag, "config disabled or missing; nothing to apply")
            stopSelf(startId)
            return START_NOT_STICKY
        }
        // Run the apply synchronously; CarrierConfig calls are fast enough to
        // fit inside the foreground-service window.
        try {
            Applier.apply(applicationContext, config)
        } catch (t: Throwable) {
            Log.e(tag, "apply failed", t)
        }

        // Re-apply on SIM/sub changes if the user wants it (default true).
        if (config.applyOnSimChange) {
            registerSubCallback()
        }
        // Keep the service around briefly so the callback can receive events;
        // we stop ourselves when idle. For a one-shot apply, stop now.
        stopSelf(startId)
        return START_NOT_STICKY
    }

    private fun registerSubCallback() {
        val tm = getSystemService(TelephonyManager::class.java) ?: return
        try {
            val cb = ActiveSubCallback { triggerReapply() }
            tm.registerTelephonyCallback(mainExecutor, cb)
            callback = cb
            Log.i(tag, "TelephonyCallback registered")
        } catch (t: Throwable) {
            Log.w(tag, "registerTelephonyCallback failed (boot/SIM receiver covers it)", t)
        }
    }

    private fun triggerReapply() {
        val config = ConfigStore.read() ?: return
        if (!config.enabled) return
        try {
            Applier.apply(applicationContext, config)
            Log.i(tag, "re-applied after active subscription change")
        } catch (t: Throwable) {
            Log.e(tag, "re-apply failed", t)
        }
    }

    override fun onDestroy() {
        callback?.let { cb ->
            val tm = getSystemService(TelephonyManager::class.java)
            try {
                tm?.unregisterTelephonyCallback(cb)
            } catch (t: Throwable) {
                Log.w(tag, "unregisterTelephonyCallback failed", t)
            }
        }
        callback = null
        super.onDestroy()
    }

    /** Listens for active-data subscription changes (covers拔卡/换卡). */
    private class ActiveSubCallback(private val onChange: () -> Unit) :
        TelephonyCallback(), TelephonyCallback.ActiveDataSubscriptionIdListener {
        override fun onActiveDataSubscriptionIdChanged(subId: Int) = onChange()
    }
}
