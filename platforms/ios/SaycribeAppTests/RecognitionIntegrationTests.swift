import XCTest
import Darwin
import Foundation
@testable import SaycribeApp

/// 有模型时跑真识别；无模型则 skip。不打印任何 token。
final class RecognitionIntegrationTests: XCTestCase {
    private var modelDir: String {
        ProcessInfo.processInfo.environment["SAYCRIBE_MODEL_DIR"]
            ?? "/Users/zjh/claude-workdir/suikou/vendor/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
    }
    private var vadPath: String {
        ProcessInfo.processInfo.environment["SAYCRIBE_VAD_PATH"]
            ?? "/Users/zjh/claude-workdir/suikou/vendor/vad/silero_vad.onnx"
    }
    private var wavPath: String {
        ProcessInfo.processInfo.environment["SAYCRIBE_WAV"]
            ?? "/Users/zjh/claude-workdir/suikou/eval/audio/t1.wav"
    }

    func testRealTranscribeMetrics() throws {
        let fm = FileManager.default
        try XCTSkipUnless(fm.fileExists(atPath: modelDir + "/model.int8.onnx"), "无 SenseVoice 模型")
        try XCTSkipUnless(fm.fileExists(atPath: vadPath), "无 VAD 模型")
        try XCTSkipUnless(fm.fileExists(atPath: wavPath), "无测试 wav")

        let pcm = try Self.readWavF32(wavPath)
        XCTAssertFalse(pcm.isEmpty)

        let t0 = CFAbsoluteTimeGetCurrent()
        let rec = try Recognizer(config: .init(modelDir: modelDir, numThreads: 2))
        let loadMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

        let peakBefore = Self.peakMemoryBytes()
        let t1 = CFAbsoluteTimeGetCurrent()
        let result = try rec.transcribe(pcm, sampleRate: 16_000)
        let wallMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        let peakAfter = Self.peakMemoryBytes()

        let audioSec = Double(pcm.count) / 16_000.0
        let rtf = (result.decodeMs > 0 ? Double(result.decodeMs) : wallMs) / 1000.0 / max(audioSec, 0.001)
        let peakMB = Double(max(peakBefore, peakAfter)) / 1_048_576.0

        let report = """
        === Saycribe iOS 识别自测 ===
        model_dir=\(modelDir)
        wav=\(wavPath)
        audio_seconds=\(String(format: "%.3f", audioSec))
        load_ms=\(String(format: "%.1f", loadMs))
        decode_ms=\(result.decodeMs)
        wall_decode_ms=\(String(format: "%.1f", wallMs))
        rtf=\(String(format: "%.3f", rtf))
        peak_memory_mb=\(String(format: "%.1f", peakMB))
        lang=\(result.lang)
        text=\(result.text)
        abi=\(ASR.abiVersion)
        """
        print(report)
        let out = URL(fileURLWithPath: "/tmp/saycribe-ios-asr-metrics.txt")
        try report.write(to: out, atomically: true, encoding: .utf8)

        XCTAssertFalse(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "识别文本为空")
        XCTAssertGreaterThan(result.decodeMs, 0)
    }

    private static func peakMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.resident_size : 0
    }

    private static func readWavF32(_ path: String) throws -> [Float] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard data.count > 44 else { throw ASRError.audioFormat }
        // 极简：找 data chunk，假定 16-bit PCM mono 16k
        var offset = 12
        var dataPos = 0
        var dataSize = 0
        var channels: Int = 0
        var rate: Int = 0
        var bps: Int = 0
        while offset + 8 <= data.count {
            let id = String(data: data.subdata(in: offset..<offset+4), encoding: .ascii) ?? ""
            let sz = Int(data.subdata(in: offset+4..<offset+8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
            if id == "fmt " {
                channels = Int(data.subdata(in: offset+10..<offset+12).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
                rate = Int(data.subdata(in: offset+12..<offset+16).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
                bps = Int(data.subdata(in: offset+22..<offset+24).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
            } else if id == "data" {
                dataPos = offset + 8
                dataSize = sz
                break
            }
            offset += 8 + sz
        }
        guard channels == 1, bps == 16, rate == 16000, dataPos > 0 else { throw ASRError.audioFormat }
        let n = dataSize / 2
        var out = [Float](repeating: 0, count: n)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: dataPos).assumingMemoryBound(to: Int16.self)
            for i in 0..<n { out[i] = Float(base[i]) / 32768.0 }
        }
        return out
    }
}
