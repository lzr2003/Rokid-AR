package com.rokid.godot;

import android.app.Activity;
import android.view.MotionEvent;
import android.view.View;

import android.util.Log;

/**
 * Rokid 触控板桥接 — 直接在 Activity 层拦截触控事件
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

    public static void init() {
        if (sInitialized) return;
        sInitialized = true;

        try {
            Class<?> godotClass = Class.forName("org.godotengine.godot.Godot");
            final Activity activity = (Activity) godotClass.getMethod("getActivity").invoke(null);
            if (activity == null) {
                Log.e("RokidTouchBridge", "Godot activity is null");
                return;
            }
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    setupTouchInterceptor(activity);
                }
            });
        } catch (Exception e) {
            Log.e("RokidTouchBridge", "Failed to init", e);
        }
    }

    private static void setupTouchInterceptor(Activity activity) {
        try {
            View decorView = activity.getWindow().getDecorView();
            decorView.setOnTouchListener(new View.OnTouchListener() {
                @Override
                public boolean onTouch(View v, MotionEvent event) {
                    handleMotionEvent(event);
                    return true;
                }
            });

            Log.i("RokidTouchBridge", "Touch interceptor registered on decor view");
        } catch (Exception e) {
            Log.e("RokidTouchBridge", "Failed to setup touch interceptor", e);
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
