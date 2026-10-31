import Foundation
import AVFoundation
import Accelerate

/// 真机 / 模拟器麦克风：AVAudioEngine → 16 kHz 单声道 float32 PCM，并暴露瞬时音量 0…1。
final class MicRecorder: NSObject, AudioRecording {
    private let engine = AVAudioEngine()
    private let targetRate: Double = 16_000
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private(set) var active = false
    /// 供 UI 弹簧缩放用的瞬时 RMS（0…1）。
    private(set) var level: Float = 0

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); level = 0; lock.unlock()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredSampleRate(targetRate)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw NSError(domain: "Saycribe.Mic", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "麦克风不可用"])
        }
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: targetRate, channels: 1, interleaved: false) else {
            throw NSError(domain: "Saycribe.Mic", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "无法创建 16k 格式"])
        }
        converter = AVAudioConverter(from: inFormat, to: outFormat)

        input.removeTap(onBus: 0)
        let bufferSize: AVAudioFrameCount = 1024
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer, outFormat: outFormat)
        }
        engine.prepare()
        try engine.start()
        active = true
    }

    func stop() -> [Float] {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        converter = nil
        active = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        lock.lock(); defer { lock.unlock() }
        let out = samples
        samples = []
        level = 0
        return out
    }

    private func append(buffer: AVAudioPCMBuffer, outFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            status.pointee = .haveData
            return buffer
        }
        converter.convert(to: out, error: &error, withInputFrom: inputBlock)
        guard error == nil, out.frameLength > 0, let ch = out.floatChannelData?[0] else { return }
        let n = Int(out.frameLength)
        var rms: Float = 0
        vDSP_rmsqv(ch, 1, &rms, vDSP_Length(n))
        // 说话常见 RMS ~0.02–0.2；映射到 0…1
        let mapped = min(1, max(0, (rms - 0.005) / 0.12))
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))
        level = mapped
        lock.unlock()
    }
}
