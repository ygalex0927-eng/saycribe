/* C ABI 自测：链接 libsaycribe_core，用真模型 + eval/audio/t1.wav
 * 构建见同目录旁注释 / 脚本；本文件提交保留。
 */
#include "saycribe_asr.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* 极简 16-bit PCM WAV 读取（仅单声道） */
static int read_wav_f32(const char *path, float **out, int32_t *n, int32_t *sr) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    unsigned char hdr[44];
    if (fread(hdr, 1, 44, f) != 44) { fclose(f); return -2; }
    if (memcmp(hdr, "RIFF", 4) || memcmp(hdr + 8, "WAVE", 4)) { fclose(f); return -3; }
    /* 找 fmt / data */
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
            data_pos = ftell(f);
            data_size = sz;
            found_data = 1;
        } else {
            fseek(f, sz, SEEK_CUR);
        }
    }
    if (!found_fmt || channels != 1 || bps != 16) { fclose(f); return -6; }
    int32_t samples = data_size / 2;
    float *pcm = (float *)malloc((size_t)samples * sizeof(float));
    if (!pcm) { fclose(f); return -7; }
    fseek(f, data_pos, SEEK_SET);
    for (int32_t i = 0; i < samples; i++) {
        int16_t s;
        if (fread(&s, 2, 1, f) != 1) { free(pcm); fclose(f); return -8; }
        pcm[i] = (float)s / 32768.0f;
    }
    fclose(f);
    *out = pcm; *n = samples; *sr = rate;
    return 0;
}

static void check(const char *label, sc_status st) {
    printf("[%s] status=%d (%s) last=%s\n", label, (int)st,
           sc_status_message(st), sc_last_error() ? sc_last_error() : "");
}

int main(int argc, char **argv) {
    const char *model_dir = argc > 1 ? argv[1] :
        "../../vendor/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09";
    const char *vad_path = argc > 2 ? argv[2] : "../../vendor/vad/silero_vad.onnx";
    const char *wav_path = argc > 3 ? argv[3] : "../../eval/audio/t1.wav";

    printf("abi=%d\n", sc_asr_abi_version());
    printf("model_dir=%s\nvad=%s\nwav=%s\n", model_dir, vad_path, wav_path);

    float *pcm = NULL; int32_t n = 0, sr = 0;
    int rc = read_wav_f32(wav_path, &pcm, &n, &sr);
    if (rc != 0) { fprintf(stderr, "read_wav failed %d\n", rc); return 1; }
    printf("wav: %d samples, sr=%d, %.2fs\n", n, sr, n / (double)sr);

    /* 错误路径：错采样率 → -4 */
    sc_recognizer_config rcg; sc_recognizer_config_default(&rcg);
    rcg.model_dir = model_dir; rcg.language = "auto";
    sc_recognizer *rec = NULL;
    sc_status st = sc_recognizer_create(&rcg, &rec);
    check("create", st);
    if (st != SC_OK || !rec) { free(pcm); return 2; }

    sc_result *bad = NULL;
    st = sc_recognizer_transcribe(rec, pcm, n, 8000, &bad);
    check("bad_sr", st);
    if (st != SC_ERR_AUDIO_FORMAT) {
        fprintf(stderr, "FAIL: expected -4 for bad sample rate\n");
        sc_recognizer_destroy(rec); free(pcm); return 3;
    }

    /* 整段识别 */
    sc_result *res = NULL;
    st = sc_recognizer_transcribe(rec, pcm, n, 16000, &res);
    check("whole", st);
    if (st == SC_OK && res) {
        printf("  text=[%s]\n  lang=[%s] audio=%.2fs decode_ms=%llu\n",
               res->text ? res->text : "", res->lang ? res->lang : "",
               res->audio_seconds, (unsigned long long)res->decode_ms);
        sc_result_free(res);
    } else {
        sc_recognizer_destroy(rec); free(pcm); return 4;
    }

    /* VAD 分段 + 逐段识别 */
    sc_vad_config vc; sc_vad_config_default(&vc);
    vc.silero_model = vad_path;
    sc_segmenter *seg = NULL;
    st = sc_segmenter_create(&vc, &seg);
    check("vad_create", st);
    if (st != SC_OK || !seg) { sc_recognizer_destroy(rec); free(pcm); return 5; }

    int32_t ready = 0;
    const int chunk = 1600; /* 100ms */
    for (int32_t i = 0; i < n; i += chunk) {
        int32_t m = (i + chunk <= n) ? chunk : (n - i);
        sc_segmenter_push(seg, pcm + i, m, &ready);
    }
    sc_segmenter_finish(seg, &ready);
    printf("segments ready=%d\n", ready);

    int seq = 0;
    sc_segment s;
    while (sc_segmenter_pop(seg, &s)) {
        sc_result *r = NULL;
        st = sc_recognizer_transcribe(rec, s.samples, s.n, 16000, &r);
        printf("  seg#%d start=%lld n=%d status=%d", seq, (long long)s.start_sample, s.n, (int)st);
        if (st == SC_OK && r) {
            printf(" text=[%s] lang=[%s] decode_ms=%llu\n",
                   r->text ? r->text : "", r->lang ? r->lang : "",
                   (unsigned long long)r->decode_ms);
            sc_result_free(r);
        } else {
            printf(" err=%s\n", sc_last_error());
        }
        seq++;
    }
    if (seq == 0) {
        fprintf(stderr, "WARN: VAD produced 0 segments (audio may be continuous); whole-path already OK\n");
    }

    /* 模型缺失 → -2 */
    sc_recognizer_config badc; sc_recognizer_config_default(&badc);
    badc.model_dir = "/tmp/saycribe-no-such-model";
    sc_recognizer *r2 = NULL;
    st = sc_recognizer_create(&badc, &r2);
    check("missing_model", st);
    if (st != SC_ERR_MODEL_MISSING) {
        fprintf(stderr, "WARN: expected -2 for missing model, got %d\n", (int)st);
    }

    sc_segmenter_destroy(seg);
    sc_recognizer_destroy(rec);
    free(pcm);
    printf("C ABI selftest DONE\n");
    return 0;
}
