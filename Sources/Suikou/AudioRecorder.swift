import AVFoundation

/// Captures the default input device and resamples to 16 kHz mono Float32 for the recognizer.
final class AudioRecorder {
    static let sampleRate = 16000.0
    /// Hard cap so a forgotten hands-free session can't grow memory forever (5 minutes).
    static let maxSamples = Int(sampleRate) * 300

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var isRunning = false

    /// Called on the audio thread with the raw RMS (0…1) of each buffer, for the HUD waveform.
    var onLevel: ((Float) -> Void)?

    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
    }

    func start() throws {
        guard !isRunning else { return }
        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        if var device = AudioDevices.resolve(uid: Settings.shared.micUID), let unit = input.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else { throw NSError(domain: "Suikou", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建音频转换器"]) }

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * Self.sampleRate / inFormat.sampleRate) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let ch = out.floatChannelData?[0] else { return }
            let chunk = UnsafeBufferPointer(start: ch, count: Int(out.frameLength))
            self.lock.withLock {
                if self.samples.count < Self.maxSamples { self.samples.append(contentsOf: chunk) }
            }

            var sum: Float = 0
            for s in chunk { sum += s * s }
            let rms = chunk.isEmpty ? 0 : (sum / Float(chunk.count)).squareRoot()
            self.onLevel?(rms)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // A leftover tap makes the next installTap assert and crash the app.
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    /// Stops capture and returns everything recorded since `start()`.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        return lock.withLock { samples }
    }
}
