package com.rokid.godot;

import android.util.Log;

import com.rokid.unitycallbridge.UnityCallBridge;

public class RokidTouchBridge {

    private static volatile boolean sInitDone = false;

    private static volatile float sDeltaX = 0.0f;
    private static volatile float sDeltaY = 0.0f;
    private static volatile int sTouchState = 0;
    private static volatile boolean sClickPending = false;
    private static final Object sLock = new Object();

    private static float sLastX = 0.0f;
    private static float sLastY = 0.0f;

    static { Log.i("RokidTouchBridge", "CLASS LOADED"); }

    public static void init() {
        if (sInitDone) return;
        sInitDone = true;

        // 1. 注册 VirtualController（args 是 List<String>，必须传 JSON 字符串）
        String regJson = "{\"name\":\"VirtualController.registerFrag\",\"args\":[" +
            "\"{\\\"name\\\":\\\"type\\\",\\\"value\\\":\\\"5\\\"}\"]}";
        Log.i("RokidTouchBridge", "registerFrag result: " + UnityCallBridge.onUnityCall(regJson));

        // 2. 注册触控回调
        String touchJson = "{\"name\":\"VirtualController.setOnTouchListener\",\"args\":[]," +
            "\"callback\":{\"name\":\"com.rokid.godot.TouchReceiver\",\"method\":\"onTouch\"}}";
        Log.i("RokidTouchBridge", "setOnTouchListener result: " + UnityCallBridge.onUnityCall(touchJson));

        // 3. 注册滚动回调
        String scrollJson = "{\"name\":\"VirtualController.setOnScrollListener\",\"args\":[]," +
            "\"callback\":{\"name\":\"com.rokid.godot.TouchReceiver\",\"method\":\"onScroll\"}}";
        Log.i("RokidTouchBridge", "setOnScrollListener result: " + UnityCallBridge.onUnityCall(scrollJson));

        Log.i("RokidTouchBridge", "VirtualController registered");
    }

    // ============ C++ JNI 调用接口 ============

    public static float getDeltaX() {
        synchronized (sLock) {
            float v = sDeltaX;
            sDeltaX = 0.0f;
            return v;
        }
    }

    public static float getDeltaY() {
        synchronized (sLock) {
            float v = sDeltaY;
            sDeltaY = 0.0f;
            return v;
        }
    }

    public static int getTouchState() {
        synchronized (sLock) {
            return sTouchState;
        }
    }

    public static boolean consumeClick() {
        synchronized (sLock) {
            if (sClickPending) {
                sClickPending = false;
                return true;
            }
            return false;
        }
    }

    // ============ TouchReceiver 回调 ============

    public static void onTouchEvent(String type, float x, float y) {
        Log.i("RokidTouchBridge", "onTouchEvent type=" + type + " x=" + x + " y=" + y);
        synchronized (sLock) {
            if ("down".equals(type)) {
                sTouchState = 1;
                sClickPending = true;
                sDeltaX = 0; sDeltaY = 0;
                sLastX = x; sLastY = y;
            } else if ("move".equals(type) || "drag".equals(type)) {
                sTouchState = 2;
                sDeltaX = x - sLastX;
                sDeltaY = y - sLastY;
                sLastX = x; sLastY = y;
            } else if ("up".equals(type)) {
                sTouchState = 0;
                sDeltaX = 0; sDeltaY = 0;
            }
        }
    }

    public static void onScrollEvent(float dx, float dy) {
        Log.i("RokidTouchBridge", "onScrollEvent dx=" + dx + " dy=" + dy);
        synchronized (sLock) {
            sDeltaX = dx;
            sDeltaY = dy;
            sTouchState = 3;
        }
    }
}
