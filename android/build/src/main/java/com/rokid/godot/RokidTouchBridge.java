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

/**
 * Rokid 触控板桥接 — 通过系统 overlay 窗口拦截触控事件
 * 需要 SYSTEM_ALERT_WINDOW 权限（debug 安装时自动授予）
 */
public class RokidTouchBridge {

    private static volatile boolean sInitialized = false;
    private static volatile float sDeltaX = 0.0f;
    private static volatile float sDeltaY = 0.0f;
    private static volatile int sTouchState = 0;
    private static volatile boolean sClickPending = false;
    private static final Object sLock = new Object();

    private static float sLastX = 0.0f;
    private static float sLastY = 0.0f;

    private static volatile boolean sOverlayReady = false;

    public static void init() {
        if (sInitialized) return;

        try {
            Class<?> godotClass = Class.forName("org.godotengine.godot.Godot");
            final Activity activity = (Activity) godotClass.getMethod("getActivity").invoke(null);
            if (activity == null) {
                Log.e("RokidTouchBridge", "Godot activity is null");
                return;
            }
            sInitialized = true;
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    setupOverlay(activity);
                }
            });
        } catch (Exception e) {
            Log.e("RokidTouchBridge", "Failed to init", e);
        }
    }

    private static void setupOverlay(final Activity activity) {
        try {
            // 检查 SYSTEM_ALERT_WINDOW 权限
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
            params.x = 0;
            params.y = 0;

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
            Log.i("RokidTouchBridge", "System overlay registered for touch interception");
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
    }

    // ------ GDExtension JNI 轮询接口 ------

    public static float getDeltaX() { synchronized (sLock) { float v = sDeltaX; sDeltaX = 0; return v; } }
    public static float getDeltaY() { synchronized (sLock) { float v = sDeltaY; sDeltaY = 0; return v; } }
    public static int getTouchState() { return sTouchState; }
    public static boolean consumeClick() {
        boolean v = sClickPending;
        sClickPending = false;
        return v;
    }
}
