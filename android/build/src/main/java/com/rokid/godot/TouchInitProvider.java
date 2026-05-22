package com.rokid.godot;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.util.Log;

public class TouchInitProvider extends ContentProvider {

    @Override
    public boolean onCreate() {
        Log.i("RokidTouchBridge", "[Step 1/5] TouchInitProvider onCreate — about to load librokid_jni.so");
        try {
            System.loadLibrary("rokid_jni");
            Log.i("RokidTouchBridge", "[Step 1/5] OK — librokid_jni.so loaded successfully");
        } catch (Exception e) {
            Log.e("RokidTouchBridge", "[Step 1/5] FAILED — librokid_jni.so load error", e);
        }
        Log.i("RokidTouchBridge", "[Step 1/5] calling RokidTouchBridge.init()");
        RokidTouchBridge.init();
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
