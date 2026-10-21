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
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        samples.withUnsafeBufferPointer {
            SherpaOnnxAcceptWaveformOffline(stream, 16000, $0.baseAddress, Int32($0.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        guard let text = result.pointee.text else { return "" }
        return String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
