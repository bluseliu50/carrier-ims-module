import android.content.Context;
import android.os.Bundle;
import android.os.PersistableBundle;
import android.telephony.CarrierConfigManager;
import android.telephony.SubscriptionInfo;
import android.telephony.SubscriptionManager;
import android.telephony.TelephonyManager;
import org.json.JSONArray;
import org.json.JSONObject;
import java.lang.reflect.Method;
import java.util.List;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;

/**
 * Root-mode CarrierConfig applier. Runs via
 *   CLASSPATH=Applier.dex app_process / Applier <action>
 * as uid 0 (root). Root holds MODIFY_PHONE_STATE implicitly, so
 * CarrierConfigManager.overrideConfig succeeds without FLAG_SYSTEM,
 * a priv-app, or any /system overlay — zero boot-loop risk.
 *
 * Logic ported from the original ImsModifier.buildBundle (Shizuku app).
 */
public class Applier {
    static final String CONFIG_PATH = "/data/adb/carrier_ims/config.json";
    static final String STATUS_PATH = "/data/adb/carrier_ims/status.json";

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

        // app_process launched from shell has no Application. Use systemMain()
        // to create a system-level ActivityThread and get a usable Context.
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thread = at.getMethod("systemMain").invoke(null);
        Context ctx = (Context) at.getMethod("getSystemContext").invoke(thread);
        if (ctx == null) { writeError("cannot get system context"); return; }
        CarrierConfigManager cm = (CarrierConfigManager) ctx.getSystemService(Context.CARRIER_CONFIG_SERVICE);
        SubscriptionManager sm = (SubscriptionManager) ctx.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE);
        TelephonyManager tm = (TelephonyManager) ctx.getSystemService(Context.TELEPHONY_SERVICE);

        if (cm == null || sm == null) { writeError("system service unavailable"); return; }

        @SuppressWarnings("unchecked")
        List<SubscriptionInfo> subs = (List<SubscriptionInfo>)
            SubscriptionManager.class.getMethod("getActiveSubscriptionInfoList").invoke(sm);
        if (subs == null || subs.isEmpty()) { writeError("no active subscriptions"); return; }

        if ("reset".equals(action)) {
            for (SubscriptionInfo sub : subs) invoke(cm, sub.getSubscriptionId(), null, false);
            writeReset(); return;
        }

        File cfgFile = new File(CONFIG_PATH);
        if (!cfgFile.exists()) { writeError("no config"); return; }
        JSONObject cfg = new JSONObject(readFile(cfgFile));
        JSONObject slots = cfg.optJSONObject("slots");
        if (slots == null) { writeError("no slots configured"); return; }

        JSONArray results = new JSONArray();
        for (SubscriptionInfo sub : subs) {
            int slot = sub.getSimSlotIndex();
            int subId = sub.getSubscriptionId();
            JSONObject sc = slots.optJSONObject(String.valueOf(slot));
            if (sc == null) continue;

            Bundle b = buildBundle(sc);
            boolean applied = false; String error = null;
            try { invoke(cm, subId, toPB(b), true); applied = true; }
            catch (Throwable pe) {
                try { invoke(cm, subId, toPB(b), false); applied = true; }
                catch (Throwable fe) { error = fe.getMessage() != null ? fe.getMessage() : fe.getClass().getSimpleName(); }
            }
            boolean ims = imsRegistered(tm, subId);
            JSONObject r = new JSONObject();
            r.put("slotIndex", slot); r.put("subId", subId);
            r.put("applied", applied); r.put("imsRegistered", ims);
            if (error != null) r.put("error", error);
            results.put(r);
        }
        JSONObject status = new JSONObject();
        status.put("lastApplyMillis", System.currentTimeMillis());
        status.put("slots", results);
        writeFile(STATUS_PATH, status.toString());
    }

    static Bundle buildBundle(JSONObject s) throws Exception {
        Bundle b = new Bundle();
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

    static PersistableBundle toPB(Bundle b) {
        PersistableBundle pb = new PersistableBundle();
        for (String k : b.keySet()) {
            Object v = b.get(k);
            if (v instanceof Boolean) pb.putBoolean(k, (Boolean)v);
            else if (v instanceof Integer) pb.putInt(k, (Integer)v);
            else if (v instanceof String) pb.putString(k, (String)v);
            else if (v instanceof int[]) pb.putIntArray(k, (int[])v);
        }
        return pb;
    }

    static void invoke(CarrierConfigManager cm, int subId, PersistableBundle v, boolean persistent) throws Throwable {
        try {
            cm.getClass().getMethod("overrideConfig", int.class, PersistableBundle.class, boolean.class)
                .invoke(cm, subId, v, persistent);
        } catch (NoSuchMethodException e) {
            cm.getClass().getMethod("overrideConfig", int.class, PersistableBundle.class)
                .invoke(cm, subId, v);
        }
    }

    static boolean imsRegistered(TelephonyManager tm, int subId) {
        try {
            TelephonyManager per = (TelephonyManager)
                TelephonyManager.class.getMethod("createForSubscriptionId", int.class).invoke(tm, subId);
            Object r = TelephonyManager.class.getMethod("isImsRegistered", int.class).invoke(per, subId);
            return r != null && (Boolean) r;
        } catch (Throwable t) { return false; }
    }

    static String readFile(File f) throws Exception {
        byte[] buf = new byte[(int)f.length()];
        FileInputStream fis = new FileInputStream(f);
        fis.read(buf); fis.close();
        return new String(buf, "UTF-8");
    }
    static void writeFile(String path, String content) throws Exception {
        FileWriter w = new FileWriter(path); w.write(content); w.close();
    }
    static void writeError(String msg) {
        try {
            JSONObject s = new JSONObject();
            s.put("lastApplyMillis", System.currentTimeMillis());
            s.put("error", msg); s.put("slots", new JSONArray());
            writeFile(STATUS_PATH, s.toString());
        } catch (Exception ignored) {}
    }
    static void writeReset() {
        try {
            JSONObject s = new JSONObject();
            s.put("lastApplyMillis", System.currentTimeMillis());
            s.put("reset", true); s.put("slots", new JSONArray());
            writeFile(STATUS_PATH, s.toString());
        } catch (Exception ignored) {}
    }
}
