/*
 * Saycribe 共享识别 C ABI（契约 v1，2026-10-30）
 * 说明文档：docs/识别接口.md
 * 实现：platforms/core（Rust，saycribe-core）以 extern "C" 导出；本头文件为语言无关契约，
 * C/C++/JNI/Swift/C# 都按它包一层。字符串一律 UTF-8，以 '\0' 结尾。
 * 音频一律 16000 Hz、单声道、float32 交错 PCM，取值 [-1, 1]。
 */
#ifndef SAYCRIBE_ASR_H
#define SAYCRIBE_ASR_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SC_ASR_ABI_VERSION 1
#define SC_ASR_SAMPLE_RATE 16000

/* 错误码：0 成功，负数失败 */
typedef enum sc_status {
    SC_OK                 = 0,
    SC_ERR_INVALID_ARG    = -1,  /* 空指针、长度<0、参数越界 */
    SC_ERR_MODEL_MISSING  = -2,  /* 模型文件不存在（model.int8.onnx / tokens.txt / silero_vad.onnx） */
    SC_ERR_MODEL_LOAD     = -3,  /* 文件在但加载失败（损坏/版本不符/sha256 不对） */
    SC_ERR_AUDIO_FORMAT   = -4,  /* 采样率不是 16000 */
    SC_ERR_AUDIO_TOO_LONG = -5,  /* 单次 transcribe 超过 300 秒，请用 VAD 分段 */
    SC_ERR_DECODE         = -6,  /* sherpa-onnx 解码无结果 */
    SC_ERR_BUSY           = -7,  /* 同一个 recognizer 正在被另一线程使用（见线程规则） */
    SC_ERR_CANCELLED      = -8,
    SC_ERR_INTERNAL       = -99
} sc_status;

typedef struct sc_recognizer sc_recognizer; /* SenseVoice 识别器，重量级，进程内建一个复用 */
typedef struct sc_segmenter  sc_segmenter;  /* Silero VAD 分段器，轻量，每次录音建一个 */

typedef struct sc_recognizer_config {
    const char *model_dir;   /* 内含 model.int8.onnx 与 tokens.txt */
    const char *language;    /* "auto"（默认）/"zh"/"en"/"ja"/"ko"/"yue"；NULL=auto */
    int32_t     num_threads; /* <=0 用默认 4 */
    const char *provider;    /* "cpu"（默认）、"cuda"、"coreml"、"nnapi"；NULL=cpu */
    int32_t     use_itn;     /* 1=逆文本正则化（数字/标点），默认 1 */
} sc_recognizer_config;

typedef struct sc_vad_config {
    const char *silero_model;      /* silero_vad.onnx 路径 */
    float       threshold;         /* 默认 0.5 */
    float       min_silence_sec;   /* 停顿多久切段，默认 0.45（Mac 同传值） */
    float       min_speech_sec;    /* 默认 0.25 */
    float       max_speech_sec;    /* 单段最长，超出强制切，默认 12 */
    float       buffer_sec;        /* 内部环形缓冲，默认 120 */
} sc_vad_config;

typedef struct sc_result {
    const char *text;          /* 识别文本（已 trim，ITN 后） */
    const char *lang;          /* 检测到的语言标签，如 "<|zh|>"；可能为空串 */
    double      audio_seconds; /* 输入时长 */
    uint64_t    decode_ms;     /* 解码耗时 */
    int64_t     start_sample;  /* 段在本次录音中的起点（样本下标）；一次性识别为 0 */
} sc_result;

typedef struct sc_segment {
    const float *samples;      /* 16k 单声道 f32，归分段器所有 */
    int32_t      n;
    int64_t      start_sample;
} sc_segment;

/* ---- 版本 / 错误 ---- */
int32_t     sc_asr_abi_version(void);                /* 返回 SC_ASR_ABI_VERSION */
const char *sc_status_message(sc_status s);         /* 中文提示，静态字符串，勿 free */
const char *sc_last_error(void);                     /* 本线程最近一次失败的详细信息，下次调用前有效 */

/* ---- 识别器 ---- */
void        sc_recognizer_config_default(sc_recognizer_config *cfg);
sc_status   sc_recognizer_create(const sc_recognizer_config *cfg, sc_recognizer **out);
void        sc_recognizer_destroy(sc_recognizer *r);  /* NULL 安全 */
/* 一次性识别一段 PCM（建议 ≤30 秒，硬上限 300 秒）。成功后用 sc_result_free 释放 *out。 */
sc_status   sc_recognizer_transcribe(sc_recognizer *r, const float *pcm, int32_t n,
                                     int32_t sample_rate, sc_result **out);
void        sc_result_free(sc_result *res);           /* NULL 安全 */

/* ---- VAD 分段 ---- */
void        sc_vad_config_default(sc_vad_config *cfg);
sc_status   sc_segmenter_create(const sc_vad_config *cfg, sc_segmenter **out);
void        sc_segmenter_destroy(sc_segmenter *s);
/* 送入任意长度 PCM（平台录音回调直接喂）。返回本次新切出的段数，段用 sc_segmenter_pop 取。 */
sc_status   sc_segmenter_push(sc_segmenter *s, const float *pcm, int32_t n, int32_t *ready);
/* 录音结束：冲刷尾部（不足 512 样本补零）。之后 pop 取最后几段。 */
sc_status   sc_segmenter_finish(sc_segmenter *s, int32_t *ready);
/* 取最早一段；无段返回 0。seg 内存有效到下一次 pop/push/finish/destroy。 */
int32_t     sc_segmenter_pop(sc_segmenter *s, sc_segment *seg);
int32_t     sc_segmenter_speaking(const sc_segmenter *s); /* 1=正在说话（HUD 用） */
void        sc_segmenter_reset(sc_segmenter *s);           /* 复用于下一次录音 */

#ifdef __cplusplus
}
#endif
#endif /* SAYCRIBE_ASR_H */
