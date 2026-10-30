import AVFoundation
import CSherpa
import CoreAudio

/// English speech with Kokoro (sherpa-onnx, on-device), played into a chosen output device — normally the virtual mic.
final class Speaker {
    /// Kokoro v0.19 speaker ids.
    static let voices: [(id: Int, name: String)] = [
        (6, "Michael · 美式男声"), (5, "Adam · 美式男声"), (9, "George · 英式男声"), (10, "Lewis · 英式男声"),
        (1, "Bella · 美式女声"), (2, "Nicole · 美式女声"), (3, "Sarah · 美式女声"), (4, "Sky · 美式女声"),
        (7, "Emma · 英式女声"), (8, "Isabella · 英式女声"),
    ]

    private let tts: OpaquePointer
    private let format: AVAudioFormat
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "suikou.tts", qos: .userInitiated)
    /// Buffers scheduled but not yet played; touched on the main thread only.
    private var pending = 0
    private(set) var deviceName = ""

    /// Main thread: true while English is playing.
    var onSpeaking: ((Bool) -> Void)?

    init?(modelDir: URL) {
        var cfg = SherpaOnnxOfflineTtsConfig()
        let strings = [
            strdup(modelDir.appendingPathComponent("model.onnx").path),
            strdup(modelDir.appendingPathComponent("voices.bin").path),
            strdup(modelDir.appendingPathComponent("tokens.txt").path),
            strdup(modelDir.appendingPathComponent("espeak-ng-data").path),
            strdup("cpu"),
        ]
        defer { strings.forEach { free(UnsafeMutableRawPointer($0)) } }
        cfg.model.kokoro.model = UnsafePointer(strings[0])
        cfg.model.kokoro.voices = UnsafePointer(strings[1])
        cfg.model.kokoro.tokens = UnsafePointer(strings[2])
        cfg.model.kokoro.data_dir = UnsafePointer(strings[3])
        cfg.model.kokoro.length_scale = 1
        cfg.model.num_threads = 4
        cfg.model.provider = UnsafePointer(strings[4])
        cfg.max_num_sentences = 1
        guard let t = SherpaOnnxCreateOfflineTts(&cfg),
              let f = AVAudioFormat(standardFormatWithSampleRate: Double(SherpaOnnxOfflineTtsSampleRate(t)), channels: 1)
        else { return nil }
        tts = t
        format = f
        engine.attach(player)
    }

    deinit { SherpaOnnxDestroyOfflineTts(tts) }

    var sampleRate: Double { format.sampleRate }

    /// Routes playback to the device with `uid` (empty: the virtual cable if there is one, else the system output).
    func start(deviceUID: String) throws {
        if engine.isRunning { player.stop(); engine.stop() }
        let outputs = AudioDevices.outputs()
        let target = outputs.first { !deviceUID.isEmpty && $0.uid == deviceUID } ?? AudioDevices.virtualCable
        if var id = target?.id, let unit = engine.outputNode.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        deviceName = target?.name ?? "系统扬声器"
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
        pending = 0
        onSpeaking?(false)
    }

    /// Queues `text`; utterances play in the order they were queued. Long text is synthesized clause by clause
    /// so the first words play while the rest is still being generated.
    func say(_ text: String, voice: Int, speed: Float) {
        for piece in Self.clauses(text) {
            queue.async { [weak self] in
                guard let self else { return }
                let samples = self.synthesize(piece, voice: voice, speed: speed)
                guard !samples.isEmpty, let buf = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
                buf.frameLength = buf.frameCapacity
                samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
                DispatchQueue.main.async {
                    guard self.engine.isRunning else { return }
                    self.pending += 1
                    self.onSpeaking?(true)
                    self.player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { _ in
                        DispatchQueue.main.async {
                            self.pending = max(0, self.pending - 1)
                            if self.pending == 0 { self.onSpeaking?(false) }
                        }
                    }
                }
            }
        }
    }

    /// Splits after sentence ends, and after commas once a piece has a few words, keeping the punctuation.
    static func clauses(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            let words = current.split(separator: " ").count
            if ".!?;".contains(ch) || (ch == "," && words >= 5) {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        // A short tail on its own sounds clipped; glue it back on.
        if out.count > 1, out.last!.split(separator: " ").count < 3 { out[out.count - 2] += " " + out.removeLast() }
        return out
    }

    /// Blocking synthesis; call off the main thread.
    func synthesize(_ text: String, voice: Int, speed: Float) -> [Float] {
        var gen = SherpaOnnxGenerationConfig()
        gen.sid = Int32(voice)
        gen.speed = speed
        gen.silence_scale = 0.2
        guard let audio = SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &gen, nil, nil) else { return [] }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        return Array(UnsafeBufferPointer(start: audio.pointee.samples, count: Int(audio.pointee.n)))
    }
}
