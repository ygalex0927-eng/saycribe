package com.saycribe.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.content.ServiceConnection
import android.os.IBinder
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

/** adb: am broadcast -a com.saycribe.android.INJECT_PCM -n com.saycribe.android/.InjectReceiver */
class InjectReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        thread(name = "saycribe-inject") {
            try {
                val f = File(context.filesDir, "inject.f32.pcm")
                if (!f.isFile) {
                    File(context.filesDir, "last_result.txt").writeText("ERR:missing inject.f32.pcm")
                    return@thread
                }
                val bytes = f.readBytes()
                val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                val pcm = FloatArray(bytes.size / 4)
                for (i in pcm.indices) pcm[i] = bb.float
                val lock = Object()
                var asr: IAsrService? = null
                val conn = object : ServiceConnection {
                    override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                        asr = IAsrService.Stub.asInterface(service)
                        synchronized(lock) { lock.notifyAll() }
                    }
                    override fun onServiceDisconnected(name: ComponentName?) { asr = null }
                }
                val i = Intent(context, AsrService::class.java)
                context.applicationContext.bindService(i, conn, Context.BIND_AUTO_CREATE)
                synchronized(lock) { if (asr == null) lock.wait(8000) }
                val svc = asr
                if (svc == null) {
                    File(context.filesDir, "last_result.txt").writeText("ERR:bind timeout")
                    return@thread
                }
                val t0 = System.currentTimeMillis()
                val out = svc.process(pcm, 16000) ?: ""
                val raw = try { svc.lastRaw() } catch (_: Exception) { "" }
                val ms = System.currentTimeMillis() - t0
                File(context.filesDir, "last_result.txt").writeText("ms=$ms\nraw=$raw\nout=$out\n")
                try { context.applicationContext.unbindService(conn) } catch (_: Exception) {}
            } catch (e: Exception) {
                File(context.filesDir, "last_result.txt").writeText("ERR:${e.message}")
            } finally {
                pending.finish()
            }
        }
    }
}