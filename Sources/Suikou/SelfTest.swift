import AVFoundation
import Foundation

/// `Saycribe.app/Contents/MacOS/Saycribe --selftest a.wav [style]` — runs recognize + clean on a file and prints timings.
enum SelfTest {
    static func run(_ args: [String]) -> Never {
        let resources = Bundle.main.resourceURL!
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
        let raw = rec.transcribe(samples)
        print(String(format: "asr    %.0fms  (%.1fs audio)  %@", Date().timeIntervalSince(t) * 1000, Double(samples.count) / 16000, raw))

        let cleaner = Cleaner(resources: resources)
        let sem = DispatchSemaphore(value: 0)
        t = Date()
        Task {
            do {
                let out = try await cleaner.clean(raw, style: style, config: .snapshot())
                print(String(format: "clean  %.0fms  [%@]  %@", Date().timeIntervalSince(t) * 1000, style.rawValue, out))
            } catch {
                print("clean failed: \(error.localizedDescription)")
            }
            sem.signal()
        }
        sem.wait()
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
