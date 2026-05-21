package com.rokid.godot;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

/**
 * 自动初始化 RokidTouchBridge — ContentProvider 在 Application.onCreate 之前调用
 */
public class TouchInitProvider extends ContentProvider {

    @Override
    public boolean onCreate() {
        Log.i("RokidTouchBridge", "TouchInitProvider onCreate — scheduling init");
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                RokidTouchBridge.init();
            }
        }, 500); // 等 Godot Activity 启动
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) { return null; }

    @Override
    public String getType(Uri uri) { return null; }

    @Override
    public Uri insert(Uri uri, ContentValues values) { return null; }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
}
