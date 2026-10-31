package com.saycribe.app

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

class MainActivity : Activity() {
    private lateinit var status: TextView
    private var asr: IAsrService? = null
    private val conn = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            asr = IAsrService.Stub.asInterface(service)
            statusAppend("ASR bound")
            if (intent?.getBooleanExtra("runInject", false) == true) runInject()
        }
        override fun onServiceDisconnected(name: ComponentName?) { asr = null }
    }

    override fun onCreate(s: Bundle?) {
        super.onCreate(s)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 48, 32, 32)
            setBackgroundColor(0xFF111111.toInt())
        }
        status = TextView(this).apply { setTextColor(0xFFFF8C00.toInt()); textSize = 15f }
        root.addView(status)
        root.addView(btn("Grant mic/notif") { requestPerms() })
        root.addView(btn("Reload config") { loadConfig() })
        root.addView(btn("IME settings") { startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) })
        root.addView(btn("Inject PCM test") { runInject() })
        setContentView(root)
        requestPerms()
        loadConfig()
        bindService(Intent(this, AsrService::class.java), conn, Context.BIND_AUTO_CREATE)
    }

    override fun onDestroy() {
        try { unbindService(conn) } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun btn(t: String, a: () -> Unit) = Button(this).apply {
        text = t; setBackgroundColor(0xFFFF8C00.toInt()); setTextColor(0xFF111111.toInt())
        setOnClickListener { a() }
    }

    private fun statusAppend(s: String) { runOnUiThread { status.text = (status.text?.toString() ?: "") + "\n" + s } }

    private fun requestPerms() {
        val need = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) need += Manifest.permission.POST_NOTIFICATIONS
        val miss = need.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (miss.isNotEmpty()) requestPermissions(miss.toTypedArray(), 1)
        else statusAppend("perms ok")
    }

    private fun loadConfig() {
        var url = "https://saycribe-api.motomotos.com"
        var hasToken = false
        val f = File(filesDir, "relay.env")
        if (f.isFile) {
            f.readLines().forEach { line ->
                val t = line.trim()
                if (t.isEmpty() || t.startsWith("#")) return@forEach
                val i = t.indexOf('=')
                if (i <= 0) return@forEach
                val k = t.substring(0, i).trim()
                val v = t.substring(i + 1).trim().trim('"')
                when (k) {
                    "RELAY_URL", "SAYCRIBE_RELAY_URL" -> url = v
                    "SAYCRIBE_TOKEN", "TOKEN", "token" -> { hasToken = v.isNotEmpty() }
                }
            }
        }
        val model = File(filesDir, "models/sense-voice/model.int8.onnx")
        val tok = if (hasToken) "loaded" else "missing"
        val mod = if (model.isFile) "ready" else "missing"
        status.text = "relay: $url\ntoken: $tok\nmodel: $mod"
        try { asr?.reloadConfig() } catch (_: Exception) {}
    }

    private fun runInject() {
        thread(name = "saycribe-inject") {
            try {
                statusAppend("inject start")
                val f = File(filesDir, "inject.f32.pcm")
                if (!f.isFile) {
                    File(filesDir, "last_result.txt").writeText("ERR:missing inject.f32.pcm")
                    statusAppend("missing inject.f32.pcm"); return@thread
                }
                val bytes = f.readBytes()
                val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                val pcm = FloatArray(bytes.size / 4)
                for (i in pcm.indices) pcm[i] = bb.float
                var tries = 0
                while (asr == null && tries++ < 40) Thread.sleep(250)
                val svc = asr
                if (svc == null) {
                    File(filesDir, "last_result.txt").writeText("ERR:bind timeout")
                    statusAppend("ASR not bound"); return@thread
                }
                statusAppend("recognizing samples=${pcm.size}")
                val t0 = System.currentTimeMillis()
                val out = svc.process(pcm, 16000) ?: ""
                val raw = try { svc.lastRaw() } catch (_: Exception) { "" }
                val ms = System.currentTimeMillis() - t0
                File(filesDir, "last_result.txt").writeText("ms=$ms\nraw=$raw\nout=$out\n")
                statusAppend("done ${ms}ms rawLen=${raw.length} outLen=${out.length}")
            } catch (e: Exception) {
                File(filesDir, "last_result.txt").writeText("ERR:${e.message}")
                statusAppend("fail ${e.message}")
            }
        }
    }
}