import Foundation
import SaycribeCore

/// Silero VAD 分段器。每次录音新建或 reset 复用；不要跨线程。
final class Segmenter {
    struct Config {
        var sileroModel: String
        var threshold: Float
        var minSilenceSec: Float
        var minSpeechSec: Float
        var maxSpeechSec: Float
        var bufferSec: Float
        init(sileroModel: String,
                    threshold: Float = 0.5, minSilenceSec: Float = 0.45,
                    minSpeechSec: Float = 0.25, maxSpeechSec: Float = 12, bufferSec: Float = 120) {
            self.sileroModel = sileroModel; self.threshold = threshold
            self.minSilenceSec = minSilenceSec; self.minSpeechSec = minSpeechSec
            self.maxSpeechSec = maxSpeechSec; self.bufferSec = bufferSec
        }
        static func defaultModelPath() -> String {
            SharedConstants.sharedContainerURL().appendingPathComponent("models/silero_vad.onnx").path
        }
    }

    private var raw: OpaquePointer?

    init(config: Config) throws {
        var cfg = sc_vad_config(silero_model: nil, threshold: 0.5, min_silence_sec: 0.45,
                                min_speech_sec: 0.25, max_speech_sec: 12, buffer_sec: 120)
        sc_vad_config_default(&cfg)
        try config.sileroModel.withCString { path in
            cfg.silero_model = path
            cfg.threshold = config.threshold
            cfg.min_silence_sec = config.minSilenceSec
            cfg.min_speech_sec = config.minSpeechSec
            cfg.max_speech_sec = config.maxSpeechSec
            cfg.buffer_sec = config.bufferSec
            var out: OpaquePointer?
            let st = sc_segmenter_create(&cfg, &out)
            guard st == SC_OK, let out else { throw ASRError.from(status: st) }
            self.raw = out
        }
    }

    deinit { sc_segmenter_destroy(raw) }

    @discardableResult
    func push(_ pcm: [Float]) throws -> Int {
        guard let raw else { throw ASRError.modelMissing }
        var ready: Int32 = 0
        let st = pcm.withUnsafeBufferPointer { sc_segmenter_push(raw, $0.baseAddress, Int32($0.count), &ready) }
        guard st == SC_OK else { throw ASRError.from(status: st) }
        return Int(ready)
    }

    @discardableResult
    func finish() throws -> Int {
        guard let raw else { throw ASRError.modelMissing }
        var ready: Int32 = 0
        let st = sc_segmenter_finish(raw, &ready)
        guard st == SC_OK else { throw ASRError.from(status: st) }
        return Int(ready)
    }

    func pop() -> SpeechSegment? {
        guard let raw else { return nil }
        var seg = sc_segment(samples: nil, n: 0, start_sample: 0)
        guard sc_segmenter_pop(raw, &seg) != 0, let ptr = seg.samples, seg.n > 0 else { return nil }
        return SpeechSegment(samples: Array(UnsafeBufferPointer(start: ptr, count: Int(seg.n))), startSample: seg.start_sample)
    }

    var isSpeaking: Bool { raw.map { sc_segmenter_speaking($0) != 0 } ?? false }
    func reset() { sc_segmenter_reset(raw) }
}
