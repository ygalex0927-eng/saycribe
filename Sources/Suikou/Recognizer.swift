import CSherpa
import Foundation

/// Local speech recognition with SenseVoice-Small (int8) through the sherpa-onnx C API.
final class Recognizer {
    private let recognizer: OpaquePointer

    init?(modelDir: URL, language: String) {
        var cfg = SherpaOnnxOfflineRecognizerConfig()
        // C strings must stay alive only until the recognizer is created; sherpa copies them.
        let model = strdup(modelDir.appendingPathComponent("model.int8.onnx").path)
        let tokens = strdup(modelDir.appendingPathComponent("tokens.txt").path)
        let lang = strdup(language)
        let provider = strdup("cpu")
        let decoding = strdup("greedy_search")
        defer { [model, tokens, lang, provider, decoding].forEach { free(UnsafeMutableRawPointer($0)) } }

        cfg.feat_config.sample_rate = 16000
        cfg.feat_config.feature_dim = 80
        cfg.model_config.sense_voice.model = UnsafePointer(model)
        cfg.model_config.sense_voice.language = UnsafePointer(lang)
        cfg.model_config.sense_voice.use_itn = 1
        cfg.model_config.tokens = UnsafePointer(tokens)
        cfg.model_config.num_threads = 4
        cfg.model_config.provider = UnsafePointer(provider)
        cfg.decoding_method = UnsafePointer(decoding)

        guard let r = SherpaOnnxCreateOfflineRecognizer(&cfg) else { return nil }
        recognizer = r
    }

    deinit { SherpaOnnxDestroyOfflineRecognizer(recognizer) }

    func transcribe(_ samples: [Float]) -> String {
        recognize(samples).text
    }

    /// Text plus the language SenseVoice detected, e.g. "<|zh|>" or "<|en|>".
    func recognize(_ samples: [Float]) -> (text: String, lang: String) {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return ("", "") }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        samples.withUnsafeBufferPointer {
            SherpaOnnxAcceptWaveformOffline(stream, 16000, $0.baseAddress, Int32($0.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return ("", "") }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        let text = result.pointee.text.map { String(cString: $0) } ?? ""
        let lang = result.pointee.lang.map { String(cString: $0) } ?? ""
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), lang)
    }
}

/// Silero VAD: cuts continuous microphone audio into utterances at pauses.
final class VoiceDetector {
    static let window = 512
    private let vad: OpaquePointer
    private var pending: [Float] = []

    init?(model: URL, minSilence: Float) {
        var cfg = SherpaOnnxVadModelConfig()
        let path = strdup(model.path)
        let provider = strdup("cpu")
        defer { [path, provider].forEach { free(UnsafeMutableRawPointer($0)) } }
        cfg.silero_vad.model = UnsafePointer(path)
        cfg.silero_vad.threshold = 0.5
        cfg.silero_vad.min_silence_duration = minSilence
        cfg.silero_vad.min_speech_duration = 0.3
        cfg.silero_vad.max_speech_duration = 12
        cfg.silero_vad.window_size = Int32(Self.window)
        cfg.sample_rate = 16000
        cfg.num_threads = 1
        cfg.provider = UnsafePointer(provider)
        guard let v = SherpaOnnxCreateVoiceActivityDetector(&cfg, 60) else { return nil }
        vad = v
    }

    deinit { SherpaOnnxDestroyVoiceActivityDetector(vad) }

    var isSpeaking: Bool { SherpaOnnxVoiceActivityDetectorDetected(vad) != 0 }

    /// Feeds 16 kHz mono audio and returns any utterances that just ended.
    func accept(_ samples: [Float]) -> [[Float]] {
        pending.append(contentsOf: samples)
        var offset = 0
        pending.withUnsafeBufferPointer { buf in
            while offset + Self.window <= buf.count {
                SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad, buf.baseAddress! + offset, Int32(Self.window))
                offset += Self.window
            }
        }
        pending.removeFirst(offset)
        return drain()
    }

    /// Ends whatever is being said now (used when interpreting stops).
    func flush() -> [[Float]] {
        SherpaOnnxVoiceActivityDetectorFlush(vad)
        return drain()
    }

    private func drain() -> [[Float]] {
        var out: [[Float]] = []
        while SherpaOnnxVoiceActivityDetectorEmpty(vad) == 0 {
            if let seg = SherpaOnnxVoiceActivityDetectorFront(vad) {
                out.append(Array(UnsafeBufferPointer(start: seg.pointee.samples, count: Int(seg.pointee.n))))
                SherpaOnnxDestroySpeechSegment(seg)
            }
            SherpaOnnxVoiceActivityDetectorPop(vad)
        }
        return out
    }
}
