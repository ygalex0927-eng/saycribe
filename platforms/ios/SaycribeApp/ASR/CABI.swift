import Foundation
import SaycribeCore

// 与 platforms/core/include/saycribe_asr.h 对齐的 Swift 侧声明。
// 真库：platforms/core 产出 libsaycribe_core.a（device/sim 各一）+ SherpaOnnxC.xcframework，只链主 App。

let SC_ASR_ABI_VERSION: Int32 = 1
let SC_ASR_SAMPLE_RATE: Int32 = 16_000

typealias sc_status = Int32
let SC_OK: sc_status = 0
let SC_ERR_INVALID_ARG: sc_status = -1
let SC_ERR_MODEL_MISSING: sc_status = -2
let SC_ERR_MODEL_LOAD: sc_status = -3
let SC_ERR_AUDIO_FORMAT: sc_status = -4
let SC_ERR_AUDIO_TOO_LONG: sc_status = -5
let SC_ERR_DECODE: sc_status = -6
let SC_ERR_BUSY: sc_status = -7
let SC_ERR_CANCELLED: sc_status = -8
let SC_ERR_INTERNAL: sc_status = -99

struct sc_recognizer_config {
    var model_dir: UnsafePointer<CChar>?
    var language: UnsafePointer<CChar>?
    var num_threads: Int32
    var provider: UnsafePointer<CChar>?
    var use_itn: Int32
}

struct sc_vad_config {
    var silero_model: UnsafePointer<CChar>?
    var threshold: Float
    var min_silence_sec: Float
    var min_speech_sec: Float
    var max_speech_sec: Float
    var buffer_sec: Float
}

struct sc_result {
    var text: UnsafePointer<CChar>?
    var lang: UnsafePointer<CChar>?
    var audio_seconds: Double
    var decode_ms: UInt64
    var start_sample: Int64
}

struct sc_segment {
    var samples: UnsafePointer<Float>?
    var n: Int32
    var start_sample: Int64
}

@_silgen_name("sc_asr_abi_version") func sc_asr_abi_version() -> Int32
@_silgen_name("sc_status_message") func sc_status_message(_ s: sc_status) -> UnsafePointer<CChar>?
@_silgen_name("sc_last_error") func sc_last_error() -> UnsafePointer<CChar>?
@_silgen_name("sc_recognizer_config_default") func sc_recognizer_config_default(_ cfg: UnsafeMutablePointer<sc_recognizer_config>)
@_silgen_name("sc_recognizer_create") func sc_recognizer_create(_ cfg: UnsafePointer<sc_recognizer_config>, _ out: UnsafeMutablePointer<OpaquePointer?>) -> sc_status
@_silgen_name("sc_recognizer_destroy") func sc_recognizer_destroy(_ r: OpaquePointer?)
@_silgen_name("sc_recognizer_transcribe") func sc_recognizer_transcribe(_ r: OpaquePointer?, _ pcm: UnsafePointer<Float>?, _ n: Int32, _ sample_rate: Int32, _ out: UnsafeMutablePointer<UnsafeMutablePointer<sc_result>?>) -> sc_status
@_silgen_name("sc_result_free") func sc_result_free(_ res: UnsafeMutablePointer<sc_result>?)
@_silgen_name("sc_vad_config_default") func sc_vad_config_default(_ cfg: UnsafeMutablePointer<sc_vad_config>)
@_silgen_name("sc_segmenter_create") func sc_segmenter_create(_ cfg: UnsafePointer<sc_vad_config>, _ out: UnsafeMutablePointer<OpaquePointer?>) -> sc_status
@_silgen_name("sc_segmenter_destroy") func sc_segmenter_destroy(_ s: OpaquePointer?)
@_silgen_name("sc_segmenter_push") func sc_segmenter_push(_ s: OpaquePointer?, _ pcm: UnsafePointer<Float>?, _ n: Int32, _ ready: UnsafeMutablePointer<Int32>?) -> sc_status
@_silgen_name("sc_segmenter_finish") func sc_segmenter_finish(_ s: OpaquePointer?, _ ready: UnsafeMutablePointer<Int32>?) -> sc_status
@_silgen_name("sc_segmenter_pop") func sc_segmenter_pop(_ s: OpaquePointer?, _ seg: UnsafeMutablePointer<sc_segment>?) -> Int32
@_silgen_name("sc_segmenter_speaking") func sc_segmenter_speaking(_ s: OpaquePointer?) -> Int32
@_silgen_name("sc_segmenter_reset") func sc_segmenter_reset(_ s: OpaquePointer?)
