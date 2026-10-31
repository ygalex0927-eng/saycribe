/* 无真库时的占位实现：签名与 saycribe_asr.h 一致，全部返回 MODEL_MISSING。 */
#include "saycribe_asr.h"
#include <stdlib.h>
static const char *g_last = "ASR stub: libsaycribe_core.so 未链接";
int32_t sc_asr_abi_version(void) { return SC_ASR_ABI_VERSION; }
const char *sc_status_message(sc_status s) { return s == SC_OK ? "ok" : "stub"; }
const char *sc_last_error(void) { return g_last; }
void sc_recognizer_config_default(sc_recognizer_config *c) { if (!c) return; c->model_dir = 0; c->language = 0; c->num_threads = 2; c->provider = 0; c->use_itn = 1; }
sc_status sc_recognizer_create(const sc_recognizer_config *c, sc_recognizer **o) { if (!c || !o) return SC_ERR_INVALID_ARG; *o = 0; return SC_ERR_MODEL_MISSING; }
void sc_recognizer_destroy(sc_recognizer *r) { (void)r; }
sc_status sc_recognizer_transcribe(sc_recognizer *r, const float *p, int32_t n, int32_t sr, sc_result **o) { (void)r; (void)p; (void)n; (void)sr; if (o) *o = 0; return SC_ERR_MODEL_MISSING; }
void sc_result_free(sc_result *r) { free(r); }
void sc_vad_config_default(sc_vad_config *c) { if (!c) return; c->silero_model = 0; c->threshold = .5f; c->min_silence_sec = .45f; c->min_speech_sec = .25f; c->max_speech_sec = 12.f; c->buffer_sec = 120.f; }
sc_status sc_segmenter_create(const sc_vad_config *c, sc_segmenter **o) { if (!c || !o) return SC_ERR_INVALID_ARG; *o = 0; return SC_ERR_MODEL_MISSING; }
void sc_segmenter_destroy(sc_segmenter *s) { (void)s; }
sc_status sc_segmenter_push(sc_segmenter *s, const float *p, int32_t n, int32_t *r) { (void)s; (void)p; (void)n; if (r) *r = 0; return SC_ERR_MODEL_MISSING; }
sc_status sc_segmenter_finish(sc_segmenter *s, int32_t *r) { (void)s; if (r) *r = 0; return SC_ERR_MODEL_MISSING; }
int32_t sc_segmenter_pop(sc_segmenter *s, sc_segment *g) { (void)s; (void)g; return 0; }
int32_t sc_segmenter_speaking(const sc_segmenter *s) { (void)s; return 0; }
void sc_segmenter_reset(sc_segmenter *s) { (void)s; }
