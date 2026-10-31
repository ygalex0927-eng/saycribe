package com.saycribe.ime

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.inputmethodservice.InputMethodService
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.saycribe.app.IAsrService
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

class SaycribeImeService : InputMethodService() {
    private val main = Handler(Looper.getMainLooper())
    private var asr: IAsrService? = null
    private var status: TextView? = null
    private var recording = false
    private var recorder: AudioRecord? = null
    private val pcmBuf = ArrayList<Float>()

    private val conn = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            asr = IAsrService.Stub.asInterface(service)
            setStatus("ready")
            try { asr?.pingRelay() } catch (_: Exception) {}
        }
        override fun onServiceDisconnected(name: ComponentName?) { asr = null; setStatus("disconnected") }
    }

    override fun onCreate() {
        super.onCreate()
        val i = Intent().setClassName("com.saycribe.android", "com.saycribe.app.AsrService")
        bindService(i, conn, Context.BIND_AUTO_CREATE)
    }

    override fun onDestroy() {
        stopRec()
        try { unbindService(conn) } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onCreateInputView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
            setBackgroundColor(0xFF111111.toInt())
        }
        status = TextView(this).apply {
            text = "connecting..."
            setTextColor(0xFFFF8C00.toInt())
            textSize = 14f
        }
        val btn = Button(this).apply {
            text = "Hold to talk"
            setBackgroundColor(0xFFFF8C00.toInt())
            setTextColor(0xFF111111.toInt())
            setOnTouchListener { _, e ->
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> { startRec(); true }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { stopRecAndProcess(); true }
                    else -> false
                }
            }
        }
        val inj = Button(this).apply {
            text = "Inject file & commit"
            setBackgroundColor(0xFFFF8C00.toInt())
            setTextColor(0xFF111111.toInt())
            setOnClickListener { injectAndCommit() }
        }
        root.addView(status)
        root.addView(btn)
        root.addView(inj)
        return root
    }

    private fun setStatus(s: String) = main.post { status?.text = s }

    /** Always persist last IME attempt (success or error) for E2E evidence. */
    private fun writeImeResult(tag: String, ms: Long, out: String, err: String? = null) {
        try {
            val sb = StringBuilder()
            sb.append("ms=").append(ms).append('\n')
            if (err != null) sb.append("err=").append(err).append('\n')
            sb.append("out=").append(out).append('\n')
            File(filesDir, "last_ime_${tag}.txt").writeText(sb.toString())
        } catch (_: Exception) {}
    }

    private fun startRec() {
        if (recording) return
        pcmBuf.clear()
        val min = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val ar = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, min.coerceAtLeast(3200))
        if (ar.state != AudioRecord.STATE_INITIALIZED) {
            ar.release()
            setStatus("mic unavailable")
            writeImeResult("mic", 0, "", "MIC_UNAVAILABLE")
            return
        }
        recorder = ar; recording = true; ar.startRecording()
        setStatus("recording...")
        thread(name = "saycribe-rec") {
            val shortBuf = ShortArray(1600)
            while (recording) {
                val n = ar.read(shortBuf, 0, shortBuf.size)
                if (n > 0) {
                    synchronized(pcmBuf) {
                        for (i in 0 until n) pcmBuf.add(shortBuf[i] / 32768f)
                    }
                }
            }
        }
        try { asr?.pingRelay() } catch (_: Exception) {}
    }

    private fun stopRec() {
        recording = false
        try { recorder?.stop() } catch (_: Exception) {}
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
    }

    private fun stopRecAndProcess() {
        stopRec()
        val pcm: FloatArray
        synchronized(pcmBuf) { pcm = pcmBuf.toFloatArray(); pcmBuf.clear() }
        if (pcm.size < 1600) {
            setStatus("too short")
            writeImeResult("mic", 0, "", "TOO_SHORT")
            return
        }
        setStatus("asr ${pcm.size / 16000f}s")
        runProcess(pcm, fromMic = true)
    }

    private fun injectAndCommit() {
        thread(name = "saycribe-ime-inject") {
            try {
                val f = File(filesDir, "inject.f32.pcm")
                if (!f.isFile) {
                    setStatus("no inject.f32.pcm")
                    writeImeResult("inject", 0, "", "NO_INJECT_FILE")
                    return@thread
                }
                val bytes = f.readBytes()
                val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                val pcm = FloatArray(bytes.size / 4)
                for (i in pcm.indices) pcm[i] = bb.float
                setStatus("inject asr ${pcm.size / 16000f}s")
                runProcess(pcm, fromMic = false)
            } catch (e: Exception) {
                val msg = e.message ?: "inject fail"
                setStatus(msg)
                writeImeResult("inject", 0, "", "EXCEPTION:$msg")
            }
        }
    }

    private fun runProcess(pcm: FloatArray, fromMic: Boolean) {
        thread(name = "saycribe-asr") {
            val tag = if (fromMic) "mic" else "inject"
            try {
                val svc = asr
                if (svc == null) {
                    setStatus("service missing")
                    writeImeResult(tag, 0, "", "SERVICE_MISSING")
                    return@thread
                }
                val t0 = System.currentTimeMillis()
                val out = svc.process(pcm, 16000) ?: ""
                val ms = System.currentTimeMillis() - t0
                if (out.startsWith("ERR:")) {
                    val code = out.removePrefix("ERR:")
                    setStatus("$tag $code")
                    writeImeResult(tag, ms, out, code)
                } else if (out.isBlank()) {
                    setStatus("$tag empty (${ms}ms)")
                    writeImeResult(tag, ms, "", "EMPTY")
                } else {
                    main.post { currentInputConnection?.commitText(out, 1) }
                    setStatus("$tag ok ${out.length}c ${ms}ms")
                    writeImeResult(tag, ms, out, null)
                }
            } catch (e: Exception) {
                val msg = e.message ?: "fail"
                setStatus(msg)
                writeImeResult(tag, 0, "", "EXCEPTION:$msg")
            }
        }
    }
}
