package com.gw4root.adbkeeper;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;

        try {
            Settings.Global.putInt(
                context.getContentResolver(), "adb_wifi_enabled", 0);
            Thread.sleep(500);
            Settings.Global.putInt(
                context.getContentResolver(), "adb_wifi_enabled", 1);
        } catch (Exception e) {
            // nothing we can do
        }
    }
}
