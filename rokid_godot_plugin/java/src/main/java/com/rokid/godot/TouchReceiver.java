package com.rokid.godot;

/**
 * BridgeMgr 反射回调目标 — 接收 VirtualController 的触控/滚轮事件
 * 回调方法签名: public static void onXxx(String json)
 */
public class TouchReceiver {

    public static void onTouch(String json) {
        RokidTouchBridge.onTouchEvent(json);
    }

    public static void onScroll(String json) {
        RokidTouchBridge.onScrollEvent(json);
    }
}
