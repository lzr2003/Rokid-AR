package com.rokid.godot;

import android.util.Log;

import com.rokid.unitycallbridge.UnityCallBridge;

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

    public static void init() {
        if (sInitDone) return;
        sInitDone = true;

        sTouchFile = new File("/data/local/tmp/rokid_touch_state.txt");

        // 1. 注册 VirtualController
        String regJson = "{\"name\":\"VirtualController.registerFrag\",\"args\":[" +
            "\"{\\\"name\\\":\\\"type\\\",\\\"value\\\":\\\"5\\\"}\"]}";
        Log.i("RokidTouchBridge", "registerFrag result: " + UnityCallBridge.onUnityCall(regJson));

        // 2. 注册触控回调
        String touchJson = "{\"name\":\"VirtualController.setOnTouchListener\",\"args\":[]," +
            "\"callback\":{\"name\":\"com.rokid.godot.TouchReceiver\",\"method\":\"onTouch\",\"param\":null}}";
        Log.i("RokidTouchBridge", "setOnTouchListener result: " + UnityCallBridge.onUnityCall(touchJson));

        // 3. 注册滚动回调
        String scrollJson = "{\"name\":\"VirtualController.setOnScrollListener\",\"args\":[]," +
            "\"callback\":{\"name\":\"com.rokid.godot.TouchReceiver\",\"method\":\"onScroll\",\"param\":null}}";
        Log.i("RokidTouchBridge", "setOnScrollListener result: " + UnityCallBridge.onUnityCall(scrollJson));

        Log.i("RokidTouchBridge", "VirtualController registered");
    }

    // TouchReceiver 回调

    public static void onTouchEvent(String type, float x, float y) {
        Log.d("RokidTouchBridge", "onTouchEvent type=" + type + " x=" + x + " y=" + y);
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
        writeState();
    }

    public static void onScrollEvent(float dx, float dy) {
        Log.d("RokidTouchBridge", "onScrollEvent dx=" + dx + " dy=" + dy);
        synchronized (sLock) {
            sDeltaX = dx;
            sDeltaY = dy;
            sTouchState = 3;
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
        } catch (Exception ex) {}
    }
}
