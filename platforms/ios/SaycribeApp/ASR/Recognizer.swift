import Foundation
import SaycribeCore

/// SenseVoice 识别器封装。约 226MB，**只允许主 App 使用，键盘扩展禁止调用**。
final class Recognizer {
    struct Config {
        var modelDir: String
        var language: String?
        var numThreads: Int32
        var provider: String?
        var useITN: Bool
        init(modelDir: String, language: String? = nil, numThreads: Int32 = 2,
                    provider: String? = nil, useITN: Bool = true) {
            self.modelDir = modelDir; self.language = language; self.numThreads = numThreads
            self.provider = provider; self.useITN = useITN
        }
        static func defaultModelsDir() -> String {
            SharedConstants.sharedContainerURL()
                .appendingPathComponent("models/\(ModelDefaults.senseVoiceDirName)", isDirectory: true).path
        }
    }

    private var raw: OpaquePointer?

    init(config: Config) throws {
        var cfg = sc_recognizer_config(model_dir: nil, language: nil, num_threads: 2, provider: nil, use_itn: 1)
        sc_recognizer_config_default(&cfg)
        try config.modelDir.withCString { dirPtr in
            try (config.language ?? "auto").withCString { langPtr in
                try (config.provider ?? "cpu").withCString { provPtr in
                    cfg.model_dir = dirPtr
                    cfg.language = langPtr
                    cfg.provider = provPtr
                    cfg.num_threads = config.numThreads
                    cfg.use_itn = config.useITN ? 1 : 0
                    var out: OpaquePointer?
                    let st = sc_recognizer_create(&cfg, &out)
                    guard st == SC_OK, let out else { throw ASRError.from(status: st) }
                    self.raw = out
                }
            }
        }
    }

    deinit { sc_recognizer_destroy(raw) }

    func transcribe(_ pcm: [Float], sampleRate: Int = ASR.sampleRate) throws -> Transcript {
        guard let raw else { throw ASRError.modelMissing }
        var result: UnsafeMutablePointer<sc_result>?
        let st: sc_status = pcm.withUnsafeBufferPointer { buf in
            sc_recognizer_transcribe(raw, buf.baseAddress, Int32(buf.count), Int32(sampleRate), &result)
        }
        defer { sc_result_free(result) }
        guard st == SC_OK, let result else { throw ASRError.from(status: st) }
        let text = result.pointee.text.map { String(cString: $0) } ?? ""
        let lang = result.pointee.lang.map { String(cString: $0) } ?? ""
        return Transcript(text: text, lang: lang, audioSeconds: result.pointee.audio_seconds,
                          decodeMs: result.pointee.decode_ms, startSample: result.pointee.start_sample)
    }
}
