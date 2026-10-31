package com.saycribe.asr

/** saycribe_asr.h JNI. Load dependency .so before jni. */
internal object NativeAsr {
    init {
        System.loadLibrary("c++_shared")
        System.loadLibrary("onnxruntime")
        System.loadLibrary("sherpa-onnx-c-api")
        System.loadLibrary("saycribe_core")
        System.loadLibrary("saycribe_jni")
    }
    @JvmStatic external fun abiVersion(): Int
    @JvmStatic external fun statusMessage(status: Int): String
    @JvmStatic external fun lastError(): String
    @JvmStatic external fun recognizerCreate(modelDir: String, language: String?, numThreads: Int, provider: String?, useItn: Boolean, out: LongArray): Int
    @JvmStatic external fun recognizerDestroy(handle: Long)
    @JvmStatic external fun transcribe(handle: Long, pcm: FloatArray, sampleRate: Int, status: IntArray): Transcript?
    @JvmStatic external fun segmenterCreate(model: String, threshold: Float, minSilence: Float, minSpeech: Float, maxSpeech: Float, bufferSec: Float, out: LongArray): Int
    @JvmStatic external fun segmenterDestroy(handle: Long)
    @JvmStatic external fun segmenterPush(handle: Long, pcm: FloatArray, offset: Int, length: Int): Int
    @JvmStatic external fun segmenterFinish(handle: Long): Int
    @JvmStatic external fun segmenterPop(handle: Long): SpeechSegment?
    @JvmStatic external fun segmenterSpeaking(handle: Long): Boolean
    @JvmStatic external fun segmenterReset(handle: Long)
}