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

/**
 * Rokid 触控板桥接 — 系统 overlay 拦截 + 文件写入供 Godot 读取
 */
public class RokidTouchBridge {

    private static volatile boolean sInitialized = false;
    private static volatile boolean sOverlayReady = false;

    private static volatile float sDeltaX = 0.0f;
    private static volatile float sDeltaY = 0.0f;
    private static volatile int sTouchState = 0;
    private static volatile boolean sClickPending = false;
    private static final Object sLock = new Object();

    private static float sLastX = 0.0f;
    private static float sLastY = 0.0f;

    private static File sTouchFile = null;

    public static void init() {
        if (sInitialized) return;
        sInitialized = true;

        try {
            Class<?> godotClass = Class.forName("org.godotengine.godot.Godot");
            // 尝试获取 Godot 单例实例，再调用 getActivity()
            Activity activity = null;
            try {
                // 先试静态方法
                activity = (Activity) godotClass.getMethod("getActivity").invoke(null);
            } catch (NullPointerException e) {
                // 不是静态方法，先拿单例
                Object godot = godotClass.getMethod("getInstance").invoke(null);
                activity = (Activity) godotClass.getMethod("getActivity").invoke(godot);
            }
            if (activity == null) {
                Log.e("RokidTouchBridge", "Godot activity is null");
                return;
            }
            sTouchFile = new File(act.getFilesDir(), "touch_state.txt");
            act.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    setupOverlay(act);
                }
            });
        } catch (Exception e) {
            Log.e("RokidTouchBridge", "Failed to init", e);
        }
    }

    private static void setupOverlay(final Activity activity) {
        try {
            if (!Settings.canDrawOverlays(activity)) {
                Log.w("RokidTouchBridge", "SYSTEM_ALERT_WINDOW not granted, requesting...");
                Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + activity.getPackageName()));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                activity.startActivity(intent);
                return;
            }

            WindowManager wm = (WindowManager) activity.getSystemService(Activity.WINDOW_SERVICE);
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            );
            params.gravity = Gravity.TOP | Gravity.LEFT;

            View touchView = new View(activity);
            touchView.setOnTouchListener(new View.OnTouchListener() {
                @Override
                public boolean onTouch(View v, MotionEvent event) {
                    handleMotionEvent(event);
                    return true;
                }
            });

            wm.addView(touchView, params);
            sOverlayReady = true;
            Log.i("RokidTouchBridge", "System overlay registered");
        } catch (SecurityException e) {
            Log.e("RokidTouchBridge", "SYSTEM_ALERT_WINDOW permission denied!", e);
        } catch (Exception e) {
            Log.e("RokidTouchBridge", "Failed to setup overlay", e);
        }
    }

    private static void handleMotionEvent(MotionEvent event) {
        float x = event.getX();
        float y = event.getY();

        synchronized (sLock) {
            switch (event.getActionMasked()) {
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
            String line;
            boolean click;
            float dx, dy;
            int state;
            synchronized (sLock) {
                dx = sDeltaX; sDeltaX = 0;
                dy = sDeltaY; sDeltaY = 0;
                state = sTouchState;
                click = sClickPending; sClickPending = false;
            }
            line = String.format("%.3f %.3f %d %d", dx, dy, state, click ? 1 : 0);
            FileWriter fw = new FileWriter(sTouchFile, false);
            fw.write(line);
            fw.close();
        } catch (Exception e) {
            // silently ignore write errors
        }
    }
}
