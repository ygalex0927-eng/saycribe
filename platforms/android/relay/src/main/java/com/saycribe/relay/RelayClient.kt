package com.saycribe.relay

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** 中转客户端（docs/中转接口.md v1.1）。baseUrl 可配置；token 由调用方从安全存储读出传入，绝不打印。 */
class RelayClient(baseUrl: String = BuildConfig.DEFAULT_RELAY_URL, private val token: String?) {
    val baseUrl: String = baseUrl.trimEnd('/')

    class RelayException(val http: Int, val code: String, message: String) : Exception("$http $code: $message")

    fun ping(): Boolean = request("GET", "/v1/ping", null, 4000).optBoolean("ok")
    fun me(): JSONObject = request("GET", "/v1/me", null, 5000)

    fun clean(transcript: String, style: String? = null, dictionary: List<String> = emptyList(), context: String? = null,
              sessionId: String? = null, seq: Int? = null, final: Boolean? = null): String {
        val b = JSONObject().put("transcript", transcript)
        style?.let { b.put("style", it) }
        if (dictionary.isNotEmpty()) b.put("dictionary", JSONArray(dictionary))
        context?.let { b.put("context", it.takeLast(300)) }
        sessionId?.let { b.put("session_id", it) }; seq?.let { b.put("seq", it) }; final?.let { b.put("final", it) }
        return request("POST", "/v1/clean", b, timeoutFor(transcript.length)).optString("text")
    }

    private fun timeoutFor(chars: Int) = 4000 + chars * 20

    private fun request(method: String, path: String, body: JSONObject?, timeoutMs: Int): JSONObject {
        val c = URL(baseUrl + path).openConnection() as HttpURLConnection
        try {
            c.requestMethod = method; c.connectTimeout = 3000; c.readTimeout = timeoutMs
            c.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            c.setRequestProperty("X-Saycribe-Platform", "android")
            token?.let { c.setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) { c.doOutput = true; c.outputStream.use { it.write(body.toString().toByteArray()) } }
            val code = c.responseCode
            val txt = (if (code in 200..299) c.inputStream else c.errorStream)?.bufferedReader()?.use { it.readText() } ?: "{}"
            val j = runCatching { JSONObject(txt) }.getOrDefault(JSONObject())
            if (code !in 200..299) {
                val e = j.optJSONObject("error")
                throw RelayException(code, e?.optString("code") ?: "http_$code", e?.optString("message") ?: "")
            }
            return j
        } finally { c.disconnect() }
    }
}
