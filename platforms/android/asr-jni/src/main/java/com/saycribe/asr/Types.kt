package com.saycribe.asr

const val SAMPLE_RATE = 16_000
const val ABI_VERSION = 1

/** 与 sc_status 对齐 */
enum class AsrStatus(val code: Int) {
    OK(0), INVALID_ARG(-1), MODEL_MISSING(-2), MODEL_LOAD(-3), AUDIO_FORMAT(-4),
    AUDIO_TOO_LONG(-5), DECODE(-6), BUSY(-7), CANCELLED(-8), INTERNAL(-99);
    companion object { fun of(c: Int) = entries.firstOrNull { it.code == c } ?: INTERNAL }
}

class AsrException(val status: AsrStatus, val detail: String) : Exception("${status.name}: $detail")

data class Transcript(val text: String, val lang: String, val audioSeconds: Double, val decodeMs: Long, val startSample: Long)

class SpeechSegment(val samples: FloatArray, val startSample: Long)

internal fun check(code: Int) { if (code != 0) throw AsrException(AsrStatus.of(code), NativeAsr.lastError()) }
