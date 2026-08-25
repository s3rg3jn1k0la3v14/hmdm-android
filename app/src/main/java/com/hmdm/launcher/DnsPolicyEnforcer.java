package com.hmdm.launcher;

import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.os.UserManager;
import android.util.Log;

public class DnsPolicyEnforcer {
    
    public static void enforceDevicePolicies(Context context) {
        try {
            DevicePolicyManager dpm = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
            ComponentName adminName = new ComponentName(context, AdminReceiver.class);
            
            if (dpm != null && dpm.isDeviceOwnerApp(context.getPackageName())) {
                dpm.addUserRestriction(adminName, UserManager.DISALLOW_CONFIG_PRIVATE_DNS);
                dpm.addUserRestriction(adminName, UserManager.DISALLOW_FACTORY_RESET);
                dpm.addUserRestriction(adminName, UserManager.DISALLOW_SAFE_BOOT);
                
                Log.i("HMDM-DNS", "SUCCESS: Private DNS, Factory Reset and Safe Boot restricted. ADB is open!");
            }
        } catch (Exception e) {
            Log.e("HMDM-DNS", "CRITICAL: Failed to enforce strict policies", e);
        }
    }

    public static void selfDestruct(Context context) {
        try {
            DevicePolicyManager dpm = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
            ComponentName adminName = new ComponentName(context, AdminReceiver.class);
            
            if (dpm != null && dpm.isDeviceOwnerApp(context.getPackageName())) {
                dpm.clearUserRestriction(adminName, UserManager.DISALLOW_CONFIG_PRIVATE_DNS);
                dpm.clearUserRestriction(adminName, UserManager.DISALLOW_FACTORY_RESET);
                dpm.clearUserRestriction(adminName, UserManager.DISALLOW_SAFE_BOOT);
                
                dpm.clearDeviceOwnerApp(context.getPackageName());
                Log.i("HMDM-DNS", "SUCCESS: Restrictions removed and Device Owner revoked!");
            }
        } catch (Exception e) {
            Log.e("HMDM-DNS", "CRITICAL: Failed to trigger kill-switch", e);
        }
    }
}
