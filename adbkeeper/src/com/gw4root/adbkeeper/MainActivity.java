package com.gw4root.adbkeeper;

import android.app.Activity;
import android.os.Bundle;
import android.provider.Settings;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView tv = new TextView(this);

        int adbWifi = -1;
        try {
            adbWifi = Settings.Global.getInt(
                getContentResolver(), "adb_wifi_enabled");
        } catch (Exception e) { }

        tv.setText("GW4 ADB Keeper\n\n"
            + "adb_wifi_enabled = " + adbWifi + "\n\n"
            + "Grant:\n"
            + "  pm grant com.gw4root.adbkeeper\n"
            + "    android.permission.WRITE_SECURE_SETTINGS");
        tv.setPadding(32, 32, 32, 32);
        tv.setTextSize(14);
        setContentView(tv);
    }
}
