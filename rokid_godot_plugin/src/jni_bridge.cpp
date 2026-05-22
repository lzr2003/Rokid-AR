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

static JavaVM* g_jvm = nullptr;

extern "C" {

jint JNI_OnLoad(JavaVM* vm, void* /*reserved*/) {
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

JavaVM* rokid_get_jvm() {
    return g_jvm;
}

} // extern "C"
