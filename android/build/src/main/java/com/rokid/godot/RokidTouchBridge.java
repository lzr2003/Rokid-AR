package com.rokid.godot;

import com.rokid.unitycallbridge.UnityCallBridge;

/**
 * Rokid 触控板桥接 — 调用 UnityCallBridge 注册 VirtualController 监听
 */
public class RokidTouchBridge {

    private static volatile boolean sInitialized = false;
    private static volatile float sDeltaX = 0.0f;
    private static volatile float sDeltaY = 0.0f;
    private static volatile int sTouchState = 0;
    private static volatile boolean sClickPending = false;
    private static final Object sLock = new Object();

    public static void init() {
        if (sInitialized) return;
        sInitialized = true;

        try {
            // 1. 注册 VirtualController (Mouse 模式)
            String json = "{\"name\":\"VirtualController.registerFrag\",\"args\":[" +
                "{\"name\":\"type\",\"value\":\"5\"}]}";
            UnityCallBridge.onUnityCall(json);

            // 2. 注册触控监听
            String touchJson = "{\"name\":\"VirtualController.setOnTouchListener\"," +
                "\"callback\":{\"name\":\"com.rokid.godot.TouchReceiver\",\"method\":\"onTouch\"}}";
            UnityCallBridge.onUnityCall(touchJson);

            // 3. 注册滚轮监听
            String scrollJson = "{\"name\":\"VirtualController.setOnScrollListener\"," +
                "\"callback\":{\"name\":\"com.rokid.godot.TouchReceiver\",\"method\":\"onScroll\"}}";
            UnityCallBridge.onUnityCall(scrollJson);

            android.util.Log.i("RokidTouchBridge", "VirtualController registered");
        } catch (Exception e) {
            android.util.Log.e("RokidTouchBridge", "Failed to init", e);
        }
    }

    // ------ TouchReceiver 回调方法 ------

    public static void onTouchEvent(String json) {
        try {
            org.json.JSONObject obj = new org.json.JSONObject(json);
            String type = obj.optString("type", "");
            float x = (float) obj.optDouble("x", 0);
            float y = (float) obj.optDouble("y", 0);

            synchronized (sLock) {
                if ("down".equals(type) || "touch".equals(type)) {
                    sTouchState = 1;
                    sClickPending = true;
                    sDeltaX = 0;
                    sDeltaY = 0;
                } else if ("move".equals(type) || "drag".equals(type)) {
                    sTouchState = 2;
                    sDeltaX = x;
                    sDeltaY = y;
                } else if ("up".equals(type)) {
                    sTouchState = 0;
                }
            }
        } catch (Exception e) {
            android.util.Log.e("RokidTouchBridge", "Parse error", e);
        }
    }

    public static void onScrollEvent(String json) {
        try {
            org.json.JSONObject obj = new org.json.JSONObject(json);
            float dx = (float) obj.optDouble("dx", 0);
            float dy = (float) obj.optDouble("dy", 0);
            synchronized (sLock) {
                sDeltaX = dx;
                sDeltaY = dy;
                sTouchState = 3; // scroll
            }
        } catch (Exception e) {
            android.util.Log.e("RokidTouchBridge", "Scroll parse error", e);
        }
    }

    // ------ GDExtension JNI 轮询接口 ------

    public static float getDeltaX() { synchronized (sLock) { return sDeltaX; } }
    public static float getDeltaY() { synchronized (sLock) { return sDeltaY; } }
    public static int getTouchState() { return sTouchState; }
    public static boolean consumeClick() {
        boolean v = sClickPending;
        sClickPending = false;
        return v;
    }
}
