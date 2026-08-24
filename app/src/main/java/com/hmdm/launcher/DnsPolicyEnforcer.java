package com.hmdm.launcher;

import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.os.UserManager;
import android.util.Log;

public class DnsPolicyEnforcer {
    private static final String TAG = "HMDM-DNS";

    public static void enforceDevicePolicies(Context context) {
        try {
            DevicePolicyManager dpm = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
            if (dpm == null) {
                Log.e(TAG, "DevicePolicyManager == null");
                return;
            }

            if (!dpm.isDeviceOwnerApp(context.getPackageName())) {
                Log.e(TAG, "Application is NOT Device Owner. Cannot enforce policies.");
                return;
            }

            ComponentName admin = new ComponentName(context, AdminReceiver.class);
            Log.i(TAG, "Attempting to set DISALLOW_CONFIG_PRIVATE_DNS...");

            dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_PRIVATE_DNS);

            boolean applied = dpm.getUserRestrictions(admin)
                    .getBoolean(UserManager.DISALLOW_CONFIG_PRIVATE_DNS, false);

            if (applied) {
                Log.i(TAG, "SUCCESS: Private DNS restriction VERIFIED active in DPM!");
            } else {
                Log.e(TAG, "FAIL: Private DNS restriction NOT PRESENT after setting it. OEM blocked it?");
            }
        } catch (Throwable e) {
            Log.e(TAG, "CRITICAL: Failed to apply Private DNS restriction", e);
        }
    }
}
