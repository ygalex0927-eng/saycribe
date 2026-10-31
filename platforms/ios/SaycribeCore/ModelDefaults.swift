import Foundation

/// 与 docs/模型下载.md 一致；sha256 已与 Mac 仓库 vendor/ 核对。
public enum ModelDefaults {
    public static let senseVoiceDirName = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"

    public static let senseVoiceONNX = ModelDownloader.Spec(
        urls: [
            URL(string: "https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/model.int8.onnx")!,
            URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/model.int8.onnx")!,
        ],
        sha256: "12ca1a2ae7ecf3e0019ef2822307ee0b5cadc9196569e379b4c4026f8205276d",
        expectedSize: 237_115_547,
        fileName: "model.int8.onnx"
    )

    public static let tokens = ModelDownloader.Spec(
        urls: [
            URL(string: "https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/tokens.txt")!,
            URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/tokens.txt")!,
        ],
        sha256: "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc",
        expectedSize: 315_894,
        fileName: "tokens.txt"
    )

    public static let sileroVAD = ModelDownloader.Spec(
        urls: [
            URL(string: "https://saycribe-api.motomotos.com/dl/models/silero_vad.onnx")!,
            URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!,
        ],
        sha256: "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6",
        expectedSize: 643_854,
        fileName: "silero_vad.onnx"
    )

    /// 整包备用：GitHub 官方 release（需解压）。
    public static let senseVoiceBundle = ModelDownloader.Spec(
        urls: [
            URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2")!,
        ],
        sha256: "7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63",
        expectedSize: 165_783_878,
        fileName: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2"
    )

    public static var requiredFiles: [ModelDownloader.Spec] { [senseVoiceONNX, tokens, sileroVAD] }
}
