package com.gamestudio100.arac_motoru;

import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.IBinder;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;

/**
 * Göz koruma filtresi: tüm ekranın üstüne dokunmaları geçiren yarı saydam
 * bir renk katmanı çizer. Android 12+ dokunma güvenliği için saydamlık en
 * fazla 0,8'dir. Son ayar saklanır; servis yeniden başlatılırsa
 * filtre aynı renkle geri gelir.
 */
public class ScreenFilterService extends Service {
    static volatile boolean running = false;
    private static final String PREFS = "arac_motoru_filter";

    private WindowManager wm;
    private View view;
    private WindowManager.LayoutParams lp;

    static void clear(Context c) {
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("on", false).apply();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        SharedPreferences p = getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        int color;
        float alpha;
        if (intent != null && intent.hasExtra("color")) {
            color = intent.getIntExtra("color", 0xFFFF8F00);
            alpha = intent.getFloatExtra("alpha", 0.3f);
            p.edit().putBoolean("on", true).putInt("color", color).putFloat("alpha", alpha).apply();
        } else {
            if (!p.getBoolean("on", false)) {
                stopSelf();
                return START_NOT_STICKY;
            }
            color = p.getInt("color", 0xFFFF8F00);
            alpha = p.getFloat("alpha", 0.3f);
        }
        if (!Settings.canDrawOverlays(this)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        alpha = Math.max(0f, Math.min(0.8f, alpha));
        if (wm == null) wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        if (view == null) {
            DisplayMetrics dm = getResources().getDisplayMetrics();
            int size = Math.max(dm.widthPixels, dm.heightPixels) + 600;
            int type = Build.VERSION.SDK_INT >= 26
                    ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    : WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY;
            lp = new WindowManager.LayoutParams(
                    size, size, type,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT);
            lp.gravity = Gravity.TOP | Gravity.START;
            lp.x = -300;
            lp.y = -300;
            lp.alpha = alpha;
            view = new View(this);
            view.setBackgroundColor(color | 0xFF000000);
            try {
                wm.addView(view, lp);
            } catch (RuntimeException e) {
                view = null;
                stopSelf();
                return START_NOT_STICKY;
            }
        } else {
            view.setBackgroundColor(color | 0xFF000000);
            lp.alpha = alpha;
            wm.updateViewLayout(view, lp);
        }
        running = true;
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        if (view != null && wm != null) {
            try {
                wm.removeView(view);
            } catch (RuntimeException ignored) {
            }
        }
        view = null;
        super.onDestroy();
    }
}
