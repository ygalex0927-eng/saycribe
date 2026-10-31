package com.saycribe.app

import android.app.Service
import android.content.Intent
import android.os.IBinder
import com.saycribe.asr.Recognizer
import com.saycribe.relay.RelayClient
import java.io.File

class AsrService : Service() {
    @Volatile private var recognizer: Recognizer? = null
    @Volatile private var lastRaw: String = ""
    @Volatile private var lastError: String = ""

    private val binder = object : IAsrService.Stub() {
        override fun abiVersion(): Int = Recognizer.abiVersion()
        override fun lastRaw(): String = lastRaw
        override fun lastError(): String = lastError
        override fun pingRelay(): Boolean = try { buildRelay().ping() } catch (e: Exception) { lastError = e.message ?: "ping"; false }
        override fun reloadConfig() {
            try { ensureRecognizer(); lastError = "" } catch (e: Exception) { lastError = e.message ?: "reload" }
        }
        override fun transcribe(pcm: FloatArray, sampleRate: Int): String {
            return try {
                val r = ensureRecognizer().transcribe(pcm, sampleRate)
                lastRaw = r.text; lastError = ""; r.text
            } catch (e: Exception) { lastError = e.message ?: "transcribe"; "" }
        }
        override fun process(pcm: FloatArray, sampleRate: Int): String {
            return try {
                val raw = ensureRecognizer().transcribe(pcm, sampleRate).text
                lastRaw = raw
                if (raw.isBlank()) { lastError = ""; return "" }
                try {
                    val cleaned = buildRelay().clean(raw)
                    lastError = ""
                    cleaned
                } catch (e: Exception) {
                    val m = e.message ?: ""
                    val offline = e is java.net.UnknownHostException || e is java.net.ConnectException ||
                        e is java.net.SocketTimeoutException || e is javax.net.ssl.SSLException ||
                        m.contains("Unable to resolve") || m.contains("failed to connect") ||
                        m.contains("Network is unreachable") || m.contains("ECONNREFUSED")
                    if (offline) { lastError = "需要联网"; "ERR:需要联网" }
                    else { lastError = m; "ERR:$m" }
                }
            } catch (e: Exception) { lastError = e.message ?: "process"; "ERR:${e.message}" }
        }
    }

    override fun onCreate() {
        super.onCreate()
        try { ensureRecognizer() } catch (e: Exception) { lastError = e.message ?: "onCreate" }
    }
    override fun onBind(intent: Intent?): IBinder = binder
    override fun onDestroy() { recognizer?.close(); recognizer = null; super.onDestroy() }

    private fun ensureRecognizer(): Recognizer {
        recognizer?.let { return it }
        val dir = File(filesDir, "models/sense-voice")
        if (!File(dir, "model.int8.onnx").isFile || !File(dir, "tokens.txt").isFile) {
            throw IllegalStateException("模型缺失")
        }
        val r = Recognizer(dir.absolutePath, language = "zh", numThreads = 2, provider = "cpu", useItn = true)
        recognizer = r
        return r
    }

    private fun buildRelay(): RelayClient {
        var url = com.saycribe.relay.BuildConfig.DEFAULT_RELAY_URL
        var token: String? = null
        val f = File(filesDir, "relay.env")
        if (f.isFile) {
            f.readLines().forEach { line ->
                val t = line.trim(); if (t.isEmpty() || t.startsWith("#")) return@forEach
                val i = t.indexOf('='); if (i <= 0) return@forEach
                val k = t.substring(0, i).trim(); val v = t.substring(i + 1).trim().trim('"')
                when (k) {
                    "RELAY_URL", "SAYCRIBE_RELAY_URL" -> url = v
                    "SAYCRIBE_TOKEN", "TOKEN", "token" -> token = v
                }
            }
        }
        return RelayClient(url, token)
    }
}
