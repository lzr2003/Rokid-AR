/**
 * 独立的 JNI 桥接库 — 唯一目的是在主线程安全获取 JavaVM
 * 架构：
 *   TouchInitProvider → System.loadLibrary("rokid_jni")
 *     → Android 调用 JNI_OnLoad(JavaVM*) ← 主线程，安全！
 *     → 存储到 g_jvm
 *   GDExtension → dlopen("librokid_jni.so") + dlsym("rokid_get_jvm")
 *     → 拿到安全 JavaVM → 任意线程 JNI 调用
 */
#include <jni.h>
#include <android/log.h>

#define TAG "RokidJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static JavaVM* g_jvm = nullptr;

extern "C" {

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* /*reserved*/) {
    LOGI("[Step 2/5] JNI_OnLoad called — JavaVM=%p", vm);
    g_jvm = vm;

    JNIEnv* env = nullptr;
    if (vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
        LOGE("[Step 2/5] FAILED: GetEnv returned error");
        return JNI_ERR;
    }
    LOGI("[Step 2/5] OK — JavaVM cached, JNI_VERSION_1_6 verified");
    return JNI_VERSION_1_6;
}

__attribute__((visibility("default"))) JavaVM* rokid_get_jvm() {
    LOGI("[Bridge] rokid_get_jvm() called — returning %p", g_jvm);
    return g_jvm;
}

} // extern "C"
