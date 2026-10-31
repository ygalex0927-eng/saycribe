import Foundation
import AVFoundation
import SaycribeCore

/// 录音协议：返回 16k 单声道 float32 PCM。
protocol AudioRecording: AnyObject {
    func start() throws
    func stop() -> [Float]
}

/// 尚未接上麦克风时的占位（返回空 PCM）。真机/模拟器用 MicRecorder。
final class PlaceholderRecorder: AudioRecording {
    private(set) var active = false
    func start() throws { active = true }
    func stop() -> [Float] { active = false; return [] }
}

/// 主 App 侧会话：键盘指令 → 录音 → VAD 分段 → SenseVoice → 中转整理 → 共享信箱。
@MainActor
final class DictationSession: ObservableObject {
    @Published private(set) var state: AppStatus.State = .idle
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var lastText: String = ""
    @Published private(set) var audioLevel: Double = 0
    @Published private(set) var recordingStartedAt: Date = Date()

    private let mailbox = SharedMailbox()
    private let relay = RelayClient()
    private let mic = MicRecorder()
    private var recorder: AudioRecording { mic }
    private var recognizer: Recognizer?
    private var revision = 0
    private var currentSession: String?
    private var levelTask: Task<Void, Never>?

    init() {
        revision = mailbox.read(AppStatus.self, from: .appStatus)?.revision ?? 0
        DarwinNotifier.shared.observe(.keyboardCommand) { [weak self] in
            Task { @MainActor in self?.handleCommand() }
        }
        Task { await preloadRecognizer() }
    }

    func handle(url: URL) {
        guard url.scheme == SharedConstants.urlScheme, url.host == "record" else { return }
        handleCommand()
    }

    func startManual() {
        currentSession = UUID().uuidString
        Task { _ = await relay.ping() }
        do {
            try recorder.start()
            recordingStartedAt = Date()
            publish(.recording)
            startLevelPolling()
        } catch {
            publish(.error, message: "无法录音：\(error.localizedDescription)")
        }
    }

    func stopManual() {
        Task { await finish() }
    }

    func cancelManual() {
        _ = recorder.stop()
        stopLevelPolling()
        publish(.idle)
    }

    private func preloadRecognizer() async {
        do {
            _ = try await ModelDownloader().ensureRequiredModels()
            recognizer = try Recognizer(config: .init(modelDir: Recognizer.Config.defaultModelsDir(), numThreads: 2))
        } catch {
            recognizer = nil
        }
    }

    private func handleCommand() {
        guard let cmd = mailbox.read(KeyboardCommand.self, from: .keyboardCommand) else { return }
        switch cmd.action {
        case .start:
            currentSession = cmd.sessionId
            Task { _ = await relay.ping() }
            do {
                try recorder.start()
                recordingStartedAt = Date()
                publish(.recording)
                startLevelPolling()
            } catch {
                publish(.error, message: "无法录音")
            }
        case .stop:
            Task { await finish() }
        case .cancel:
            _ = recorder.stop()
            stopLevelPolling()
            publish(.idle)
        }
    }

    private func finish() async {
        stopLevelPolling()
        let pcm = recorder.stop()
        publish(.recognizing)
        do {
            let text = try await recognize(pcm)
            publish(.cleaning)
            let r = try await relay.clean(transcript: text, style: ConfigStore.shared.style,
                                          dictionary: ConfigStore.shared.dictionary)
            lastText = r.text
            publish(.done, text: r.text)
        } catch let e as ASRError {
            publish(.error, message: e.userMessage)
        } catch let e as RelayError {
            publish(.error, message: e.userMessage)
        } catch {
            publish(.error, message: "识别失败")
        }
    }

    private func recognize(_ pcm: [Float]) async throws -> String {
        if pcm.isEmpty { return "" }
        let maxDirect = 12 * ASR.sampleRate
        if pcm.count <= maxDirect {
            guard let recognizer else { throw ASRError.modelMissing }
            return try recognizer.transcribe(pcm).text
        }
        let seg = try Segmenter(config: .init(sileroModel: Segmenter.Config.defaultModelPath()))
        _ = try seg.push(pcm)
        _ = try seg.finish()
        guard let recognizer else { throw ASRError.modelMissing }
        var parts: [String] = []
        while let s = seg.pop() {
            let t = try recognizer.transcribe(s.samples).text
            if !t.isEmpty { parts.append(t) }
        }
        return parts.joined(separator: "")
    }

    private func publish(_ s: AppStatus.State, text: String? = nil, message: String? = nil) {
        state = s
        statusMessage = message ?? ""
        if let text { lastText = text }
        revision += 1
        try? mailbox.write(AppStatus(state: s, sessionId: currentSession, text: text, message: message, revision: revision),
                           to: .appStatus)
    }

    private func startLevelPolling() {
        stopLevelPolling()
        levelTask = Task { @MainActor in
            while !Task.isCancelled {
                audioLevel = Double(mic.level)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func stopLevelPolling() {
        levelTask?.cancel()
        levelTask = nil
        audioLevel = 0
    }

    /// DEBUG：用本地 wav 跑识别→中转，不经麦克风（真机缺权限时冒烟）。
    func runFixturePipeline(wavURL: URL) async {
        let container = SharedConstants.sharedContainerURL()
        let marker = container.appendingPathComponent("e2e-result.txt")
        let docsMarker = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("e2e-result.txt")
        func writeMarker(_ s: String) {
            let body = s + "container=\(container.path)\n"
            try? body.write(to: marker, atomically: true, encoding: .utf8)
            try? body.write(to: docsMarker, atomically: true, encoding: .utf8)
        }
        writeMarker("status=start\nwav=\(wavURL.path)\nexists=\(FileManager.default.fileExists(atPath: wavURL.path))\nmodelDir=\(Recognizer.Config.defaultModelsDir())\n")
        publish(.recognizing)
        do {
            if recognizer == nil {
                // 跳过下载，直接用已拷进容器的模型
                recognizer = try Recognizer(config: .init(modelDir: Recognizer.Config.defaultModelsDir(), numThreads: 2))
            }
            let pcm = try Self.readWavF32(wavURL)
            writeMarker("status=pcm\nsamples=\(pcm.count)\n")
            let text = try await recognize(pcm)
            writeMarker("status=asr\nraw=\(text)\n")
            publish(.cleaning)
            let r = try await relay.clean(transcript: text, style: ConfigStore.shared.style,
                                          dictionary: ConfigStore.shared.dictionary)
            lastText = r.text
            publish(.done, text: r.text)
            writeMarker("status=ok\nraw=\(text)\nclean=\(r.text)\n")
        } catch let e as ASRError {
            publish(.error, message: e.userMessage)
            writeMarker("status=asr_error\nmsg=\(e.userMessage)\n")
        } catch let e as RelayError {
            publish(.error, message: e.userMessage)
            writeMarker("status=relay_error\ncase=\(String(describing: e))\nmsg=\(e.userMessage)\n")
        } catch {
            publish(.error, message: "fixture 失败：\(error.localizedDescription)")
            writeMarker("status=error\nmsg=\(error.localizedDescription)\n")
        }
    }


    /// DEBUG：真麦克风录 N 秒 → 识别 → 中转（主 App 内，不经键盘插入）。
    func runMicPipeline(seconds: Double) async {
        let container = SharedConstants.sharedContainerURL()
        let marker = container.appendingPathComponent("e2e-result.txt")
        let docsMarker = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("e2e-result.txt")
        func writeMarker(_ s: String) {
            let body = s + "container=\(container.path)\n"
            try? body.write(to: marker, atomically: true, encoding: .utf8)
            try? body.write(to: docsMarker, atomically: true, encoding: .utf8)
        }
        writeMarker("status=mic_start\nseconds=\(seconds)\n")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try recorder.start()
            publish(.recording)
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            let pcm = recorder.stop()
            writeMarker("status=mic_pcm\nsamples=\(pcm.count)\n")
            guard !pcm.isEmpty else {
                writeMarker("status=error\nmsg=empty_pcm_mic_permission_or_silence\n")
                publish(.error, message: "麦克风无数据（权限或静音）")
                return
            }
            publish(.recognizing)
            if recognizer == nil {
                recognizer = try Recognizer(config: .init(modelDir: Recognizer.Config.defaultModelsDir(), numThreads: 2))
            }
            let text = try await recognize(pcm)
            writeMarker("status=asr\nraw=\(text)\n")
            publish(.cleaning)
            let r = try await relay.clean(transcript: text, style: ConfigStore.shared.style,
                                          dictionary: ConfigStore.shared.dictionary)
            lastText = r.text
            publish(.done, text: r.text)
            writeMarker("status=ok\nsource=mic\nraw=\(text)\nclean=\(r.text)\n")
        } catch let e as ASRError {
            publish(.error, message: e.userMessage)
            writeMarker("status=asr_error\nmsg=\(e.userMessage)\n")
        } catch let e as RelayError {
            publish(.error, message: e.userMessage)
            writeMarker("status=relay_error\ncase=\(String(describing: e))\nmsg=\(e.userMessage)\n")
        } catch {
            publish(.error, message: error.localizedDescription)
            writeMarker("status=error\nmsg=\(error.localizedDescription)\n")
        }
    }

    private static func readWavF32(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else { throw ASRError.audioFormat }
        var offset = 12
        var dataOffset = 44
        var bits: Int = 16
        var ch: Int = 1
        var rate: Int = 16000
        while offset + 8 <= data.count {
            let id = String(data: data[offset..<offset+4], encoding: .ascii) ?? ""
            let size = Int(data.subdata(in: offset+4..<offset+8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
            if id == "fmt " {
                ch = Int(data.subdata(in: offset+10..<offset+12).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
                rate = Int(data.subdata(in: offset+12..<offset+16).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
                bits = Int(data.subdata(in: offset+22..<offset+24).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
            } else if id == "data" {
                dataOffset = offset + 8
                break
            }
            offset += 8 + size + (size % 2)
        }
        guard bits == 16, ch == 1 else { throw ASRError.audioFormat }
        let pcmData = data[dataOffset...]
        var floats: [Float] = []
        floats.reserveCapacity(pcmData.count / 2)
        for i in stride(from: 0, to: pcmData.count - 1, by: 2) {
            let s = Int16(pcmData[pcmData.startIndex + i]) | (Int16(pcmData[pcmData.startIndex + i + 1]) << 8)
            floats.append(Float(s) / 32768.0)
        }
        if rate != ASR.sampleRate {
            // 极简线性重采样
            let ratio = Double(ASR.sampleRate) / Double(rate)
            let n = Int(Double(floats.count) * ratio)
            var out = [Float](repeating: 0, count: n)
            for i in 0..<n {
                let src = Double(i) / ratio
                let j = Int(src)
                let f = Float(src - Double(j))
                let a = floats[min(j, floats.count-1)]
                let b = floats[min(j+1, floats.count-1)]
                out[i] = a * (1 - f) + b * f
            }
            return out
        }
        return floats
    }

}
