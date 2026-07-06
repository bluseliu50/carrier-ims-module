import android.os.IBinder;
import android.os.PersistableBundle;
import android.system.Os;
import android.telephony.CarrierConfigManager;
import android.telephony.SubscriptionInfo;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.List;

/**
 * Root-mode CarrierConfig applier. Runs via
 *   CLASSPATH=Applier.dex app_process / Applier <action>
 *
 * CRITICAL: app_process starts as root (uid 0). Android's process management
 * SIGKILLs uid-0 app_process within ~1s. We IMMEDIATELY drop to shell uid
 * (2000) via Os.setuid — shell uid is not killed, and it has
 * MODIFY_PHONE_STATE + READ_PHONE_STATE assigned in platform.xml.
 *
 * Uses ServiceManager directly (no Context / ActivityThread / AMS interaction)
 * to get the carrier_config and isub binder services.
 *
 * Logic ported from ImsModifier.buildBundle (original Shizuku app).
 */
public class Applier {
    static final String CONFIG_PATH = "/data/adb/carrier_ims/config.json";

    static final String K_NR_THR_BW = "nr_advanced_threshold_bandwidth_khz_int";
    static final String K_NR_ADV_BANDS = "additional_nr_advanced_bands_int_array";
    static final String K_5G_ICON = "5g_icon_configuration_string";
    static final String K_NR_PCO = "nr_advanced_capable_pco_id_int";
    static final String K_NR_INC_LTE = "include_lte_for_nr_advanced_threshold_bandwidth_bool";
    static final int NR_THR_5GA = 110000;
    static final String NR_ICON_5GA =
        "connected_mmwave:5G_Plus,connected:5G,connected_rrc_idle:5G,not_restricted_rrc_idle:5G,not_restricted_rrc_con:5G";
    static final int[] NR_BANDS_CN = {1,3,8,28,41,78,79};
    static final String K_MCC_OVERRIDE = "country_mcc_override";
    static final String MCC_CN = "460";

    public static void main(String[] args) throws Throwable {
        String action = (args.length > 0) ? args[0] : "apply";

        // ---- Read config AS ROOT (before dropping privileges) ----
        File cfgFile = new File(CONFIG_PATH);
        if (!cfgFile.exists()) {
            System.out.println("{\"ok\":false,\"error\":\"no config file\"}");
            return;
        }
        JSONObject cfg = new JSONObject(readFile(cfgFile));
        JSONObject slots = cfg.optJSONObject("slots");
        if (slots == null || slots.length() == 0) {
            System.out.println("{\"ok\":false,\"error\":\"no slots configured\"}");
            return;
        }

        // ---- CRITICAL: Drop to shell uid (2000) IMMEDIATELY ----
        // Root (uid 0) app_process gets SIGKILL by Android process management.
        // Shell uid (2000) survives and has MODIFY_PHONE_STATE.
        Os.setgid(2000);
        Os.setuid(2000);

        // ---- Get services via ServiceManager (no Context needed) ----
        Object ccLoader = getService("carrier_config", "ICarrierConfigLoader");
        Object isub = getService("isub", "ISub");

        if (ccLoader == null) {
            System.out.println("{\"ok\":false,\"error\":\"carrier_config service unavailable\"}");
            return;
        }
        if (isub == null) {
            System.out.println("{\"ok\":false,\"error\":\"isub service unavailable\"}");
            return;
        }

        // ---- Get active subscriptions ----
        List<SubscriptionInfo> subs = getSubscriptions(isub);
        if (subs == null || subs.isEmpty()) {
            System.out.println("{\"ok\":false,\"error\":\"no active subscriptions\"}");
            return;
        }

        // ---- Apply for each subscription ----
        JSONArray results = new JSONArray();
        for (SubscriptionInfo sub : subs) {
            int slot = sub.getSimSlotIndex();
            int subId = sub.getSubscriptionId();
            JSONObject sc = slots.optJSONObject(String.valueOf(slot));
            if (sc == null) continue;

            PersistableBundle bundle = buildBundle(sc);
            boolean applied = false;
            String error = null;

            // Try persistent first; fall back to non-persistent (same as Shizuku app).
            try {
                overrideConfig(ccLoader, subId, bundle, true);
                applied = true;
            } catch (Throwable pe) {
                try {
                    overrideConfig(ccLoader, subId, bundle, false);
                    applied = true;
                } catch (Throwable fe) {
                    error = fe.getMessage() != null ? fe.getMessage() : fe.getClass().getSimpleName();
                }
            }

            JSONObject r = new JSONObject();
            r.put("slotIndex", slot);
            r.put("subId", subId);
            r.put("applied", applied);
            if (error != null) r.put("error", error);
            results.put(r);
        }

        JSONObject status = new JSONObject();
        status.put("lastApplyMillis", System.currentTimeMillis());
        status.put("slots", results);
        System.out.println(status.toString());
    }

    // ---- Service helpers ----

    static Object getService(String serviceName, String aidlName) {
        try {
            Class<?> smClass = Class.forName("android.os.ServiceManager");
            IBinder binder = (IBinder) smClass
                .getMethod("getService", String.class)
                .invoke(null, serviceName);
            if (binder == null) return null;

            // Try known package prefixes for the Stub class
            String[] prefixes = {
                "android.telephony.",
                "com.android.internal.telephony.",
                "com.android.internal.telephony.ims.",
            };
            for (String prefix : prefixes) {
                try {
                    Class<?> stubClass = Class.forName(prefix + aidlName + "$Stub");
                    return stubClass
                        .getMethod("asInterface", IBinder.class)
                        .invoke(null, binder);
                } catch (ClassNotFoundException ignored) { }
            }
        } catch (Exception e) {
            System.out.println("{\"ok\":false,\"error\":\"getService " + serviceName + ": " + e.getClass().getSimpleName() + "\"}");
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    static List<SubscriptionInfo> getSubscriptions(Object isub) {
        try {
            try {
                // Android 12+: 2-arg version (callingPackage, featureId)
                Method m = isub.getClass()
                    .getMethod("getActiveSubscriptionInfoList", String.class, String.class);
                return (List<SubscriptionInfo>) m.invoke(isub, "com.android.shell", null);
            } catch (NoSuchMethodException e) {
                // Older: 1-arg version
                Method m = isub.getClass()
                    .getMethod("getActiveSubscriptionInfoList", String.class);
                return (List<SubscriptionInfo>) m.invoke(isub, "com.android.shell");
            }
        } catch (Exception e) {
            return null;
        }
    }

    static void overrideConfig(Object loader, int subId, PersistableBundle bundle, boolean persistent) throws Throwable {
        try {
            Method m = loader.getClass()
                .getMethod("overrideConfig", int.class, PersistableBundle.class, boolean.class);
            m.invoke(loader, subId, bundle, persistent);
        } catch (InvocationTargetException e) {
            throw e.getCause();
        } catch (NoSuchMethodException e) {
            try {
                Method m = loader.getClass()
                    .getMethod("overrideConfig", int.class, PersistableBundle.class);
                m.invoke(loader, subId, bundle);
            } catch (InvocationTargetException e2) {
                throw e2.getCause();
            }
        }
    }

    // ---- Bundle building (ported from ImsModifier.buildBundle) ----

    static PersistableBundle buildBundle(JSONObject s) throws Exception {
        PersistableBundle b = new PersistableBundle();
        if (s.optBoolean("tiktokNetworkFix", false)) {
            b.putString(CarrierConfigManager.KEY_SIM_COUNTRY_ISO_OVERRIDE_STRING, "cn");
            b.putString(K_MCC_OVERRIDE, MCC_CN);
        }
        if (s.optBoolean("volte", true)) {
            b.putBoolean(CarrierConfigManager.KEY_CARRIER_VOLTE_AVAILABLE_BOOL, true);
            b.putBoolean(CarrierConfigManager.KEY_EDITABLE_ENHANCED_4G_LTE_BOOL, true);
            b.putBoolean(CarrierConfigManager.KEY_HIDE_ENHANCED_4G_LTE_BOOL, false);
            b.putBoolean(CarrierConfigManager.KEY_HIDE_LTE_PLUS_DATA_ICON_BOOL, false);
        }
        if (s.optBoolean("show4gForLte", false)) b.putBoolean("show_4g_for_lte_data_icon_bool", true);
        if (s.optBoolean("vt", true)) b.putBoolean(CarrierConfigManager.KEY_CARRIER_VT_AVAILABLE_BOOL, true);
        if (s.optBoolean("ut", true)) b.putBoolean(CarrierConfigManager.KEY_CARRIER_SUPPORTS_SS_OVER_UT_BOOL, true);
        if (s.optBoolean("crossSim", true)) {
            b.putBoolean(CarrierConfigManager.KEY_CARRIER_CROSS_SIM_IMS_AVAILABLE_BOOL, true);
            b.putBoolean(CarrierConfigManager.KEY_ENABLE_CROSS_SIM_CALLING_ON_OPPORTUNISTIC_DATA_BOOL, true);
        }
        if (s.optBoolean("vowifi", true)) {
            b.putBoolean(CarrierConfigManager.KEY_CARRIER_WFC_IMS_AVAILABLE_BOOL, true);
            b.putBoolean(CarrierConfigManager.KEY_CARRIER_WFC_SUPPORTS_WIFI_ONLY_BOOL, true);
            b.putBoolean(CarrierConfigManager.KEY_EDITABLE_WFC_MODE_BOOL, true);
            b.putBoolean(CarrierConfigManager.KEY_EDITABLE_WFC_ROAMING_MODE_BOOL, true);
            b.putBoolean("show_wifi_calling_icon_in_status_bar_bool", true);
            b.putInt("wfc_spn_format_idx_int", 6);
        }
        if (s.optBoolean("vonr", true)) {
            b.putBoolean(CarrierConfigManager.KEY_VONR_ENABLED_BOOL, true);
            b.putBoolean(CarrierConfigManager.KEY_VONR_SETTING_VISIBILITY_BOOL, true);
        }
        if (s.optBoolean("fiveGnr", true)) {
            b.putIntArray(CarrierConfigManager.KEY_CARRIER_NR_AVAILABILITIES_INT_ARRAY,
                new int[]{CarrierConfigManager.CARRIER_NR_AVAILABILITY_NSA, CarrierConfigManager.CARRIER_NR_AVAILABILITY_SA});
            if (s.optBoolean("fiveGPlusIcon", true)) {
                b.putInt(K_NR_THR_BW, NR_THR_5GA);
                b.putBoolean(K_NR_INC_LTE, false);
                b.putIntArray(K_NR_ADV_BANDS, NR_BANDS_CN);
                b.putString(K_5G_ICON, NR_ICON_5GA);
                b.putInt(K_NR_PCO, 0);
            }
            if (s.optBoolean("fiveGThresholds", true)) {
                b.putIntArray(CarrierConfigManager.KEY_5G_NR_SSRSRP_THRESHOLDS_INT_ARRAY,
                    new int[]{-128,-118,-108,-98});
            }
        }
        return b;
    }

    static String readFile(File f) throws Exception {
        byte[] buf = new byte[(int)f.length()];
        FileInputStream fis = new FileInputStream(f);
        fis.read(buf);
        fis.close();
        return new String(buf, "UTF-8");
    }
}
