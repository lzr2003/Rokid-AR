package com.rokid.godot;

import android.util.Log;
import org.json.JSONObject;

/**
 * BridgeMgr 反射回调目标 — 接收 VirtualController 的触控事件
 * 回调方法签名: public static void onXxx(String json)
 * BridgeMgr 通过 Class.forName + Method.invoke 调用
 */
public class TouchReceiver {

    static { Log.i("TouchReceiver", "CLASS LOADED"); }

    public static void onTouch(String json) {
        Log.i("TouchReceiver", "onTouch CALLED: " + (json != null ? json.substring(0, Math.min(100, json.length())) : "null"));
        try {
            JSONObject obj = new JSONObject(json);
            String type = obj.optString("type", "");
            float x = (float) obj.optDouble("x", 0);
            float y = (float) obj.optDouble("y", 0);
            RokidTouchBridge.onTouchEvent(type, x, y);
        } catch (Exception e) {
            Log.e("TouchReceiver", "onTouch parse error", e);
        }
    }

    public static void onScroll(String json) {
        Log.i("TouchReceiver", "onScroll CALLED");
        try {
            JSONObject obj = new JSONObject(json);
            float dx = (float) obj.optDouble("dx", 0);
            float dy = (float) obj.optDouble("dy", 0);
            RokidTouchBridge.onScrollEvent(dx, dy);
        } catch (Exception e) {
            Log.e("TouchReceiver", "onScroll parse error", e);
        }
    }
}
