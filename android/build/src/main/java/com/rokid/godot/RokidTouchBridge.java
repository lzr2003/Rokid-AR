package com.rokid.godot;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import android.graphics.PixelFormat;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.util.Log;

import java.io.File;
import java.io.FileWriter;

public class RokidTouchBridge {

    private static volatile boolean sInitDone = false;

    private static volatile float sDeltaX = 0.0f;
    private static volatile float sDeltaY = 0.0f;
    private static volatile int sTouchState = 0;
    private static volatile boolean sClickPending = false;
    private static final Object sLock = new Object();

    private static float sLastX = 0.0f;
    private static float sLastY = 0.0f;

    private static File sTouchFile = null;

    private static Activity getGodotActivity() {
        try {
            Class<?> c = Class.forName("org.godotengine.godot.Godot");
            try {
                return (Activity) c.getMethod("getActivity").invoke(null);
            } catch (NullPointerException e) {
                Object inst = c.getMethod("getInstance").invoke(null);
                return (Activity) c.getMethod("getActivity").invoke(inst);
            }
        } catch (Exception e) {
            Log.e("RokidTouchBridge", "getGodotActivity failed", e);
            return null;
        }
    }

    public static void init() {
        if (sInitDone) return;
        sInitDone = true;

        final Activity activity = getGodotActivity();
        if (activity == null) {
            Log.e("RokidTouchBridge", "Godot activity is null");
            return;
        }
        sTouchFile = new File(activity.getFilesDir(), "touch_state.txt");
        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                setupOverlay(activity);
            }
        });
    }

    private static void setupOverlay(final Activity a) {
        try {
            if (!Settings.canDrawOverlays(a)) {
                Log.w("RokidTouchBridge", "SYSTEM_ALERT_WINDOW not granted, requesting...");
                Intent i = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + a.getPackageName()));
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                a.startActivity(i);
                return;
            }

            WindowManager wm = (WindowManager) a.getSystemService(Activity.WINDOW_SERVICE);
            WindowManager.LayoutParams p = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            );
            p.gravity = Gravity.TOP | Gravity.LEFT;

            View v = new View(a);
            v.setOnTouchListener(new View.OnTouchListener() {
                @Override
                public boolean onTouch(View vv, MotionEvent e) {
                    handleTouch(e);
                    return true;
                }
            });
            wm.addView(v, p);
            Log.i("RokidTouchBridge", "System overlay registered");
        } catch (SecurityException e) {
            Log.e("RokidTouchBridge", "permission denied", e);
        } catch (Exception e) {
            Log.e("RokidTouchBridge", "setupOverlay failed", e);
        }
    }

    private static void handleTouch(MotionEvent e) {
        float x = e.getX();
        float y = e.getY();
        synchronized (sLock) {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    sTouchState = 1;
                    sClickPending = true;
                    sDeltaX = 0;
                    sDeltaY = 0;
                    sLastX = x;
                    sLastY = y;
                    break;
                case MotionEvent.ACTION_MOVE:
                    sTouchState = 2;
                    sDeltaX = x - sLastX;
                    sDeltaY = y - sLastY;
                    sLastX = x;
                    sLastY = y;
                    break;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    sTouchState = 0;
                    sDeltaX = 0;
                    sDeltaY = 0;
                    break;
            }
        }
        writeState();
    }

    private static void writeState() {
        if (sTouchFile == null) return;
        try {
            float dx, dy;
            int state;
            boolean click;
            synchronized (sLock) {
                dx = sDeltaX; sDeltaX = 0;
                dy = sDeltaY; sDeltaY = 0;
                state = sTouchState;
                click = sClickPending; sClickPending = false;
            }
            String line = String.format("%.3f %.3f %d %d", dx, dy, state, click ? 1 : 0);
            FileWriter fw = new FileWriter(sTouchFile, false);
            fw.write(line);
            fw.close();
        } catch (Exception ex) {
            // ignore
        }
    }
}
