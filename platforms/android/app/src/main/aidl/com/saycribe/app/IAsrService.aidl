package com.saycribe.app;
// IME 进程通过 Binder 调用；模型只在 :asr 进程加载
interface IAsrService {
    int abiVersion();
    String transcribe(in float[] pcm, int sampleRate);
}
