import AVFoundation
import Foundation

/// `Saycribe.app/Contents/MacOS/Saycribe --selftest a.wav [style]` — runs recognize + clean on a file and prints timings.
enum SelfTest {
    /// `SUIKOU_RESOURCES=…/Saycribe.app/Contents/Resources` lets a bare `swift build` binary find the models.
    static var resources: URL {
        ProcessInfo.processInfo.environment["SUIKOU_RESOURCES"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.resourceURL!
    }

    static func run(_ args: [String]) -> Never {
        let resources = Self.resources
        guard args.count >= 1, let samples = load(URL(fileURLWithPath: args[0])) else {
            print("usage: --selftest file.wav [chat|email|code|notes]"); exit(2)
        }
        let style = AppStyle(rawValue: args.count > 1 ? args[1] : "notes") ?? .notes

        var t = Date()
        guard let rec = Recognizer(modelDir: resources.appendingPathComponent("models/sense-voice"), language: Settings.shared.asrLanguage) else {
            print("recognizer failed to load"); exit(1)
        }
        print(String(format: "load   %.0fms", Date().timeIntervalSince(t) * 1000))
        t = Date()
        let seconds = Double(samples.count) / 16000
        let vadURL = seconds >= Segmenter.longThresholdSeconds ? resources.appendingPathComponent("models/vad/silero_vad.onnx") : nil
        let parts = Segmenter.transcribe(samples, recognizer: rec, vadModel: vadURL)
        let raw = Segmenter.join(parts)
        print(String(format: "asr    %.0fms  (%.1fs audio, %d segments)  %@", Date().timeIntervalSince(t) * 1000, seconds, parts.count, raw))
        for (i, p) in parts.enumerated() { print("  seg\(i + 1): \(p)") }

        Settings.shared.ensureRelayConfigured()
        let cleaner = Cleaner(resources: resources)
        let config = LLMConfig.snapshot()
        let sem = DispatchSemaphore(value: 0)

        // #1: warm keep-alive, then measure clean (press-to-text proxy after preconnect).
        t = Date()
        Task {
            do {
                let ver = try await cleaner.ping(baseURL: config.baseURL)
                print(String(format: "ping   %.0fms  api_version=%@", Date().timeIntervalSince(t) * 1000, ver))
            } catch {
                print("ping failed: \(error.localizedDescription)")
            }
            sem.signal()
        }
        sem.wait()

        t = Date()
        Task {
            do {
                let sessionId = UUID().uuidString
                let out = try await Segmenter.cleanAll(parts) { piece, seq, context, final in
                    try await cleaner.clean(piece, style: style, config: config,
                                            sessionId: sessionId, seq: seq, context: context, final: final)
                }
                print(String(format: "clean  %.0fms  [%@]  %@", Date().timeIntervalSince(t) * 1000, style.rawValue, out))
            } catch {
                print("clean failed: \(error.localizedDescription)")
            }
            sem.signal()
        }
        sem.wait()

        // Second clean on keep-alive connection (preconnect already done).
        t = Date()
        Task {
            do {
                let out = try await cleaner.clean(raw, style: style, config: config, sessionId: UUID().uuidString, seq: 0, final: true)
                print(String(format: "clean2 %.0fms (after warm)  %@", Date().timeIntervalSince(t) * 1000, out))
            } catch {
                print("clean2 failed: \(error.localizedDescription)")
            }
            sem.signal()
        }
        sem.wait()
        exit(0)
    }

    /// `--interpret in.wav out.wav`: VAD → recognize → DeepSeek interpret → Kokoro, one line per sentence, English audio to out.wav.
    static func interpret(_ args: [String]) -> Never {
        let resources = Bundle.main.resourceURL!
        guard args.count >= 2, let samples = load(URL(fileURLWithPath: args[0])) else {
            print("usage: --interpret in.wav out.wav"); exit(2)
        }
        var t = Date()
        guard let rec = Recognizer(modelDir: resources.appendingPathComponent("models/sense-voice"), language: ProcessInfo.processInfo.environment["ASR_LANG"] ?? "zh"),
              let vad = VoiceDetector(model: resources.appendingPathComponent("models/vad/silero_vad.onnx"), minSilence: 0.45),
              let speaker = Speaker(modelDir: resources.appendingPathComponent("models/kokoro"))
        else { print("models failed to load"); exit(1) }
        print(String(format: "load   %.0fms", Date().timeIntervalSince(t) * 1000))

        var segments: [[Float]] = []
        for start in stride(from: 0, to: samples.count, by: 1600) {
            segments += vad.accept(Array(samples[start..<min(start + 1600, samples.count)]))
        }
        segments += vad.flush()

        let cleaner = Cleaner(resources: resources)
        let config = LLMConfig.snapshot()
        var english: [Float] = []
        var context: [String] = []
        let sem = DispatchSemaphore(value: 0)
        for seg in segments {
            t = Date()
            let (zh, lang) = rec.recognize(seg)
            let asrMs = Date().timeIntervalSince(t) * 1000
            var en = ""
            t = Date()
            Task {
                en = (try? await cleaner.interpret(zh, context: context, config: config)) ?? "<failed>"
                sem.signal()
            }
            sem.wait()
            let llmMs = Date().timeIntervalSince(t) * 1000
            t = Date()
            let voice = speaker.synthesize(en, voice: Settings.shared.interpretVoice, speed: Float(Settings.shared.interpretSpeed))
            let ttsMs = Date().timeIntervalSince(t) * 1000
            english += voice + [Float](repeating: 0, count: Int(speaker.sampleRate * 0.4))
            context = Array((context + [zh]).suffix(3))
            print(String(format: "%.1fs %@ asr %.0fms · llm %.0fms · tts %.0fms (%.1fs audio)\n  %@\n  → %@",
                         Double(seg.count) / 16000, lang, asrMs, llmMs, ttsMs, Double(voice.count) / speaker.sampleRate, zh, en))
        }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: speaker.sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(english.count))!
        buf.frameLength = buf.frameCapacity
        english.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: english.count) }
        do {
            try AVAudioFile(forWriting: URL(fileURLWithPath: args[1]), settings: fmt.settings).write(from: buf)
        } catch {
            print("write failed: \(error)"); exit(1)
        }
        exit(0)
    }

    private static func load(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: file.processingFormat, to: out),
              let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: inBuf)) != nil,
              let outBuf = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: AVAudioFrameCount(Double(file.length) * 16000 / file.processingFormat.sampleRate) + 64)
        else { return nil }
        var fed = false
        conv.convert(to: outBuf, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
    }
}
