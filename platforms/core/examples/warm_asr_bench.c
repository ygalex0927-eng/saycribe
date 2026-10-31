/* 预热后连续 3 次整段+VAD；同一 recognizer / 每次新建 OfflineStream（与 Swift 一致）
 * 用法: warm_asr_bench model_dir vad.onnx wav [language=auto]
 */
#include "saycribe_asr.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static int read_wav_f32(const char *path, float **out, int32_t *n, int32_t *sr) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    unsigned char hdr[44];
    if (fread(hdr, 1, 44, f) != 44) { fclose(f); return -2; }
    fseek(f, 12, SEEK_SET);
    int16_t channels = 0, bps = 0;
    int32_t rate = 0, data_size = 0;
    int found_fmt = 0, found_data = 0;
    long data_pos = 0;
    while (!found_data) {
        unsigned char ch[8];
        if (fread(ch, 1, 8, f) != 8) { fclose(f); return -4; }
        int32_t sz; memcpy(&sz, ch + 4, 4);
        if (!memcmp(ch, "fmt ", 4)) {
            unsigned char fmt[16];
            if (sz < 16 || fread(fmt, 1, 16, f) != 16) { fclose(f); return -5; }
            if (sz > 16) fseek(f, sz - 16, SEEK_CUR);
            memcpy(&channels, fmt + 2, 2);
            memcpy(&rate, fmt + 4, 4);
            memcpy(&bps, fmt + 14, 2);
            found_fmt = 1;
        } else if (!memcmp(ch, "data", 4)) {
            data_pos = ftell(f); data_size = sz; found_data = 1;
        } else fseek(f, sz, SEEK_CUR);
    }
    if (!found_fmt || channels != 1 || bps != 16) { fclose(f); return -6; }
    int32_t samples = data_size / 2;
    float *pcm = (float *)malloc((size_t)samples * sizeof(float));
    if (!pcm) { fclose(f); return -7; }
    fseek(f, data_pos, SEEK_SET);
    for (int32_t i = 0; i < samples; i++) {
        int16_t s; if (fread(&s, 2, 1, f) != 1) { free(pcm); fclose(f); return -8; }
        pcm[i] = (float)s / 32768.0f;
    }
    fclose(f); *out = pcm; *n = samples; *sr = rate; return 0;
}

static void one_round(sc_recognizer *rec, sc_segmenter *seg, const float *pcm, int32_t n, int round) {
    sc_result *res = NULL;
    sc_status st = sc_recognizer_transcribe(rec, pcm, n, 16000, &res);
    printf("run%d whole status=%d text=[%s] lang=[%s] decode_ms=%llu\n",
           round, (int)st,
           (st == SC_OK && res && res->text) ? res->text : "",
           (st == SC_OK && res && res->lang) ? res->lang : "",
           (unsigned long long)(st == SC_OK && res ? res->decode_ms : 0));
    sc_result_free(res);

    sc_segmenter_reset(seg);
    int32_t ready = 0;
    sc_segmenter_push(seg, pcm, n, &ready);
    sc_segmenter_finish(seg, &ready);
    sc_segment s; int si = 0;
    while (sc_segmenter_pop(seg, &s)) {
        res = NULL;
        st = sc_recognizer_transcribe(rec, s.samples, s.n, 16000, &res);
        printf("run%d vad#%d start=%lld n=%d status=%d text=[%s] lang=[%s] decode_ms=%llu\n",
               round, si++, (long long)s.start_sample, (int)s.n, (int)st,
               (st == SC_OK && res && res->text) ? res->text : "",
               (st == SC_OK && res && res->lang) ? res->lang : "",
               (unsigned long long)(st == SC_OK && res ? res->decode_ms : 0));
        sc_result_free(res);
    }
}

int main(int argc, char **argv) {
    const char *model_dir = argc > 1 ? argv[1] : "../../vendor/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09";
    const char *vad_path = argc > 2 ? argv[2] : "../../vendor/vad/silero_vad.onnx";
    const char *wav_path = argc > 3 ? argv[3] : "../../eval/audio/t1.wav";
    const char *language = argc > 4 ? argv[4] : "auto";

    float *pcm = NULL; int32_t n = 0, sr = 0;
    if (read_wav_f32(wav_path, &pcm, &n, &sr) != 0) { fprintf(stderr, "wav fail\n"); return 1; }
    printf("wav=%.2fs sr=%d lang_cfg=%s\n", n / (double)sr, sr, language);

    sc_recognizer_config rc; sc_recognizer_config_default(&rc);
    rc.model_dir = model_dir; rc.language = language; rc.num_threads = 4; rc.use_itn = 1;
    sc_recognizer *rec = NULL;
    if (sc_recognizer_create(&rc, &rec) != SC_OK) {
        fprintf(stderr, "create fail: %s\n", sc_last_error()); return 1;
    }
    sc_vad_config vc; sc_vad_config_default(&vc); vc.silero_model = vad_path;
    sc_segmenter *seg = NULL;
    if (sc_segmenter_create(&vc, &seg) != SC_OK) {
        fprintf(stderr, "vad fail: %s\n", sc_last_error()); return 1;
    }

    printf("--- warmup (discard) ---\n");
    one_round(rec, seg, pcm, n, -1);
    printf("--- timed x3 ---\n");
    for (int i = 0; i < 3; i++) one_round(rec, seg, pcm, n, i);

    sc_segmenter_destroy(seg);
    sc_recognizer_destroy(rec);
    free(pcm);
    return 0;
}
