package com.saycribe.asr

/** Silero VAD 分段器，每次录音一个，单线程使用。 */
class Segmenter(sileroModel: String, threshold: Float = 0.5f, minSilenceSec: Float = 0.45f,
                minSpeechSec: Float = 0.25f, maxSpeechSec: Float = 12f, bufferSec: Float = 120f) : AutoCloseable {
    private var handle: Long
    init {
        val out = LongArray(1)
        check(NativeAsr.segmenterCreate(sileroModel, threshold, minSilenceSec, minSpeechSec, maxSpeechSec, bufferSec, out))
        handle = out[0]
    }
    fun push(pcm: FloatArray, offset: Int = 0, length: Int = pcm.size): Int { val r = NativeAsr.segmenterPush(handle, pcm, offset, length); if (r < 0) check(r); return r }
    fun finish(): Int { val r = NativeAsr.segmenterFinish(handle); if (r < 0) check(r); return r }
    fun pop(): SpeechSegment? = NativeAsr.segmenterPop(handle)
    val isSpeaking: Boolean get() = NativeAsr.segmenterSpeaking(handle)
    fun reset() = NativeAsr.segmenterReset(handle)
    override fun close() { if (handle != 0L) { NativeAsr.segmenterDestroy(handle); handle = 0 } }
}
