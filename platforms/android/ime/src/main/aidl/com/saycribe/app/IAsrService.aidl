package com.saycribe.app;

interface IAsrService {
    int abiVersion();
    String transcribe(in float[] pcm, int sampleRate);
    String process(in float[] pcm, int sampleRate);
    String lastRaw();
    String lastError();
    boolean pingRelay();
    void reloadConfig();
}