import Foundation
import SaycribeCore

enum ASRError: Error, Equatable {
    case invalidArgument, modelMissing, modelLoad, audioFormat, audioTooLong
    case decode, busy, cancelled, internalError
    case other(Int32)

    init(status s: Int32) { self = .from(status: s) }

    static func from(status s: sc_status) -> ASRError {
        switch s {
        case SC_ERR_INVALID_ARG: return .invalidArgument
        case SC_ERR_MODEL_MISSING: return .modelMissing
        case SC_ERR_MODEL_LOAD: return .modelLoad
        case SC_ERR_AUDIO_FORMAT: return .audioFormat
        case SC_ERR_AUDIO_TOO_LONG: return .audioTooLong
        case SC_ERR_DECODE: return .decode
        case SC_ERR_BUSY: return .busy
        case SC_ERR_CANCELLED: return .cancelled
        case SC_ERR_INTERNAL: return .internalError
        default: return .other(s)
        }
    }

    var userMessage: String {
        // C ABI sc_status_message 当前为英文；面向用户的文案在 Swift 侧中文化。
        let zh: String = {
            switch self {
            case .invalidArgument: return "参数无效"
            case .modelMissing: return "模型缺失，请先下载"
            case .modelLoad: return "模型加载失败，请删除后重下"
            case .audioFormat: return "音频格式不对（需要 16k 单声道）"
            case .audioTooLong: return "音频过长，请分段"
            case .decode: return "识别解码失败"
            case .busy: return "识别器正忙"
            case .cancelled: return "已取消"
            case .internalError: return "内部错误"
            case .other(let s): return "错误(\(s))"
            }
        }()
        let detail = sc_last_error().map { String(cString: $0) } ?? ""
        return detail.isEmpty ? zh : "\(zh)（\(detail)）"
    }
}

struct Transcript: Equatable {
    var text: String
    var lang: String
    var audioSeconds: Double
    var decodeMs: UInt64
    var startSample: Int64
}

struct SpeechSegment {
    var samples: [Float]
    var startSample: Int64
}

enum ASR {
    static var abiVersion: Int32 { sc_asr_abi_version() }
    static let sampleRate = Int(SC_ASR_SAMPLE_RATE)
}
