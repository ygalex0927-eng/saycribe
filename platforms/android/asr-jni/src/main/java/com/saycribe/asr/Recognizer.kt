package com.saycribe.asr

/** SenseVoice 识别器（约 300MB 内存）。只在主 App 的 :asr 进程内建一个；IME 进程禁止创建。 */
class Recognizer(modelDir: String, language: String = "auto", numThreads: Int = 2, provider: String = "cpu", useItn: Boolean = true) : AutoCloseable {
    private var handle: Long
    init {
        val out = LongArray(1)
        check(NativeAsr.recognizerCreate(modelDir, language, numThreads, provider, useItn, out))
        handle = out[0]
    }
    @Synchronized fun transcribe(pcm: FloatArray, sampleRate: Int = SAMPLE_RATE): Transcript {
        val st = IntArray(1)
        val r = NativeAsr.transcribe(handle, pcm, sampleRate, st)
        check(st[0]); return r ?: throw AsrException(AsrStatus.DECODE, "null result")
    }
    @Synchronized override fun close() { if (handle != 0L) { NativeAsr.recognizerDestroy(handle); handle = 0 } }
    companion object { fun abiVersion() = NativeAsr.abiVersion() }
}
