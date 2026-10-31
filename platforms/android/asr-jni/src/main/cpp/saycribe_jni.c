/* JNI 封装 saycribe_asr.h（契约 v1）。Java 侧：com.saycribe.asr.NativeAsr */
#include <jni.h>
#include <stdlib.h>
#include "saycribe_asr.h"

#define FN(name) Java_com_saycribe_asr_NativeAsr_##name

static jstring jstr(JNIEnv *e, const char *s) { return (*e)->NewStringUTF(e, s ? s : ""); }

JNIEXPORT jint JNICALL FN(abiVersion)(JNIEnv *e, jclass c) { (void)e; (void)c; return sc_asr_abi_version(); }
JNIEXPORT jstring JNICALL FN(statusMessage)(JNIEnv *e, jclass c, jint s) { (void)c; return jstr(e, sc_status_message((sc_status)s)); }
JNIEXPORT jstring JNICALL FN(lastError)(JNIEnv *e, jclass c) { (void)c; return jstr(e, sc_last_error()); }

/* out[0] = handle；返回 sc_status */
JNIEXPORT jint JNICALL FN(recognizerCreate)(JNIEnv *e, jclass c, jstring dir, jstring lang,
                                           jint threads, jstring provider, jboolean itn, jlongArray out) {
    (void)c;
    if (!dir || !out) return SC_ERR_INVALID_ARG;
    sc_recognizer_config cfg; sc_recognizer_config_default(&cfg);
    const char *d = (*e)->GetStringUTFChars(e, dir, 0);
    const char *l = lang ? (*e)->GetStringUTFChars(e, lang, 0) : 0;
    const char *p = provider ? (*e)->GetStringUTFChars(e, provider, 0) : 0;
    cfg.model_dir = d; cfg.language = l; cfg.provider = p;
    if (threads > 0) cfg.num_threads = threads;
    cfg.use_itn = itn ? 1 : 0;
    sc_recognizer *r = 0;
    sc_status st = sc_recognizer_create(&cfg, &r);
    (*e)->ReleaseStringUTFChars(e, dir, d);
    if (l) (*e)->ReleaseStringUTFChars(e, lang, l);
    if (p) (*e)->ReleaseStringUTFChars(e, provider, p);
    jlong h = (jlong)(intptr_t)r;
    (*e)->SetLongArrayRegion(e, out, 0, 1, &h);
    return st;
}
JNIEXPORT void JNICALL FN(recognizerDestroy)(JNIEnv *e, jclass c, jlong h) { (void)e; (void)c; sc_recognizer_destroy((sc_recognizer *)(intptr_t)h); }

/* 成功返回 Transcript 对象；失败返回 null，状态写入 status[0] */
JNIEXPORT jobject JNICALL FN(transcribe)(JNIEnv *e, jclass c, jlong h, jfloatArray pcm, jint sr, jintArray status) {
    (void)c;
    jint st = SC_ERR_INVALID_ARG; jobject obj = 0;
    if (h && pcm) {
        jsize n = (*e)->GetArrayLength(e, pcm);
        jfloat *buf = (*e)->GetFloatArrayElements(e, pcm, 0);
        sc_result *res = 0;
        st = sc_recognizer_transcribe((sc_recognizer *)(intptr_t)h, buf, n, sr, &res);
        (*e)->ReleaseFloatArrayElements(e, pcm, buf, JNI_ABORT);
        if (st == SC_OK && res) {
            jclass k = (*e)->FindClass(e, "com/saycribe/asr/Transcript");
            jmethodID ctor = (*e)->GetMethodID(e, k, "<init>", "(Ljava/lang/String;Ljava/lang/String;DJJ)V");
            obj = (*e)->NewObject(e, k, ctor, jstr(e, res->text), jstr(e, res->lang),
                                  res->audio_seconds, (jlong)res->decode_ms, (jlong)res->start_sample);
        }
        sc_result_free(res);
    }
    if (status) (*e)->SetIntArrayRegion(e, status, 0, 1, &st);
    return obj;
}

JNIEXPORT jint JNICALL FN(segmenterCreate)(JNIEnv *e, jclass c, jstring model, jfloat th, jfloat minSil,
                                          jfloat minSp, jfloat maxSp, jfloat bufSec, jlongArray out) {
    (void)c;
    if (!model || !out) return SC_ERR_INVALID_ARG;
    sc_vad_config cfg; sc_vad_config_default(&cfg);
    const char *m = (*e)->GetStringUTFChars(e, model, 0);
    cfg.silero_model = m;
    if (th > 0) cfg.threshold = th;
    if (minSil > 0) cfg.min_silence_sec = minSil;
    if (minSp > 0) cfg.min_speech_sec = minSp;
    if (maxSp > 0) cfg.max_speech_sec = maxSp;
    if (bufSec > 0) cfg.buffer_sec = bufSec;
    sc_segmenter *s = 0;
    sc_status st = sc_segmenter_create(&cfg, &s);
    (*e)->ReleaseStringUTFChars(e, model, m);
    jlong h = (jlong)(intptr_t)s;
    (*e)->SetLongArrayRegion(e, out, 0, 1, &h);
    return st;
}
JNIEXPORT void JNICALL FN(segmenterDestroy)(JNIEnv *e, jclass c, jlong h) { (void)e; (void)c; sc_segmenter_destroy((sc_segmenter *)(intptr_t)h); }

/* 返回 ready 段数（>=0）或负 sc_status */
JNIEXPORT jint JNICALL FN(segmenterPush)(JNIEnv *e, jclass c, jlong h, jfloatArray pcm, jint off, jint len) {
    (void)c;
    if (!h || !pcm || off < 0 || len < 0 || off + len > (*e)->GetArrayLength(e, pcm)) return SC_ERR_INVALID_ARG;
    jfloat *buf = (*e)->GetFloatArrayElements(e, pcm, 0);
    int32_t ready = 0;
    sc_status st = sc_segmenter_push((sc_segmenter *)(intptr_t)h, buf + off, len, &ready);
    (*e)->ReleaseFloatArrayElements(e, pcm, buf, JNI_ABORT);
    return st == SC_OK ? ready : st;
}
JNIEXPORT jint JNICALL FN(segmenterFinish)(JNIEnv *e, jclass c, jlong h) {
    (void)e; (void)c; int32_t ready = 0;
    sc_status st = sc_segmenter_finish((sc_segmenter *)(intptr_t)h, &ready);
    return st == SC_OK ? ready : st;
}
/* 取一段（拷贝到 Java），无段返回 null */
JNIEXPORT jobject JNICALL FN(segmenterPop)(JNIEnv *e, jclass c, jlong h) {
    (void)c;
    sc_segment seg;
    if (!h || !sc_segmenter_pop((sc_segmenter *)(intptr_t)h, &seg) || !seg.samples || seg.n <= 0) return 0;
    jfloatArray arr = (*e)->NewFloatArray(e, seg.n);
    (*e)->SetFloatArrayRegion(e, arr, 0, seg.n, seg.samples);
    jclass k = (*e)->FindClass(e, "com/saycribe/asr/SpeechSegment");
    jmethodID ctor = (*e)->GetMethodID(e, k, "<init>", "([FJ)V");
    return (*e)->NewObject(e, k, ctor, arr, (jlong)seg.start_sample);
}
JNIEXPORT jboolean JNICALL FN(segmenterSpeaking)(JNIEnv *e, jclass c, jlong h) { (void)e; (void)c; return sc_segmenter_speaking((const sc_segmenter *)(intptr_t)h) ? JNI_TRUE : JNI_FALSE; }
JNIEXPORT void JNICALL FN(segmenterReset)(JNIEnv *e, jclass c, jlong h) { (void)e; (void)c; sc_segmenter_reset((sc_segmenter *)(intptr_t)h); }
