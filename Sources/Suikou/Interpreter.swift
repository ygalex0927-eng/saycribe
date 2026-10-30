import AppKit
import SwiftUI

/// Meeting interpreter: microphone (Chinese) → VAD cuts at pauses → SenseVoice → DeepSeek → Kokoro → virtual mic (English).
/// Meeting apps (Zoom, 腾讯会议…) pick the virtual cable (BlackHole) as their microphone, so the others hear only English.
final class Interpreter: ObservableObject {
    /// Set by the Coordinator; the settings page uses it for preview and re-routing.
    static weak var shared: Interpreter?

    struct Line: Identifiable {
        let id: Int
        let zh: String
        var en: String?
        var failed = false
        /// From the end of the sentence to its English being queued for playback.
        var ms: Int?
    }

    enum Phase: Equatable { case off, loading, listening, hearing, speaking }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var lines: [Line] = []
    @Published private(set) var outputName = ""
    @Published private(set) var error: String?
    var isOn: Bool { phase != .off }

    private let recorder = AudioRecorder()
    private let cleaner: Cleaner
    private let resources: URL
    private let recognizer: () -> Recognizer?
    private var speaker: Speaker?
    private var vad: VoiceDetector?
    /// Captured at start so the work queue never reads the coordinator's property.
    private var asr: Recognizer?
    private let work = DispatchQueue(label: "suikou.interpret", qos: .userInitiated)
    /// Chains sentences so their English is spoken in the order they were said, even if DeepSeek answers out of order.
    private var tail: Task<Void, Never>?
    private var nextID = 0
    private var speaking = false
    private var hearing = false
    private let settings = Settings.shared
    private lazy var panel = InterpreterPanel(interpreter: self)

    init(resources: URL, cleaner: Cleaner, recognizer: @escaping () -> Recognizer?) {
        self.resources = resources
        self.cleaner = cleaner
        self.recognizer = recognizer
        recorder.onChunk = { [weak self] chunk in self?.work.async { self?.feed(chunk) } }
    }

    func toggle() { isOn ? stop() : start() }

    func start() {
        guard !isOn else { return }
        error = nil
        guard !settings.apiKey.isEmpty else { fail("未设置 DeepSeek API Key"); return }
        guard let asr = recognizer() else { fail("语音模型还在加载，请稍候"); return }
        self.asr = asr
        phase = .loading
        panel.show()
        let resources = self.resources, needSpeaker = speaker == nil
        work.async {
            let vad = VoiceDetector(model: resources.appendingPathComponent("models/vad/silero_vad.onnx"), minSilence: 0.45)
            let speaker = needSpeaker ? Speaker(modelDir: resources.appendingPathComponent("models/kokoro")) : nil
            DispatchQueue.main.async { self.begin(vad: vad, newSpeaker: speaker) }
        }
    }

    private func begin(vad: VoiceDetector?, newSpeaker: Speaker?) {
        guard phase == .loading else { return } // stopped while loading
        if let newSpeaker {
            newSpeaker.onSpeaking = { [weak self] on in self?.speaking = on; self?.refreshPhase() }
            speaker = newSpeaker
        }
        guard let vad, let speaker else { fail("同传模型加载失败"); return }
        self.vad = vad
        do {
            try speaker.start(deviceUID: settings.interpretOutputUID)
            outputName = speaker.deviceName
            try recorder.start()
        } catch {
            speaker.stop()
            fail("音频设备不可用：\(error.localizedDescription)")
            return
        }
        cleaner.warmUp(apiKey: settings.apiKey)
        phase = .listening
    }

    func stop() {
        guard isOn else { return }
        recorder.stop()
        phase = .off
        hearing = false
        // Finish the sentence that was in progress; queued English still plays out.
        work.async { [weak self] in
            guard let self, let vad = self.vad else { return }
            for seg in vad.flush() { self.process(seg) }
        }
    }

    /// Re-routes the English voice after the output device setting changes.
    func outputChanged() {
        guard isOn, let speaker else { return }
        try? speaker.start(deviceUID: settings.interpretOutputUID)
        outputName = speaker.deviceName
    }

    /// Speaks a sample sentence through the current output, for the settings page.
    func preview() {
        let voice = settings.interpretVoice, speed = Float(settings.interpretSpeed), uid = settings.interpretOutputUID
        let resources = self.resources, needSpeaker = speaker == nil
        work.async {
            let fresh = needSpeaker ? Speaker(modelDir: resources.appendingPathComponent("models/kokoro")) : nil
            DispatchQueue.main.async {
                if let fresh {
                    fresh.onSpeaking = { [weak self] on in self?.speaking = on; self?.refreshPhase() }
                    self.speaker = fresh
                }
                guard let speaker = self.speaker else { return }
                if !self.isOn { try? speaker.start(deviceUID: uid) }
                speaker.say("Hi everyone, this is how I will sound in the meeting.", voice: voice, speed: speed)
            }
        }
    }

    // MARK: - Pipeline

    /// Work queue.
    private func feed(_ chunk: [Float]) {
        guard let vad else { return }
        let segments = vad.accept(chunk)
        let nowHearing = vad.isSpeaking
        if nowHearing != hearing {
            hearing = nowHearing
            DispatchQueue.main.async { self.refreshPhase() }
        }
        for seg in segments { process(seg) }
    }

    /// Work queue: one finished utterance.
    private func process(_ seg: [Float]) {
        guard let recognizer = asr else { return }
        let ended = Date()
        let (raw, lang) = recognizer.recognize(seg)
        let core = raw.filter { !$0.isPunctuation && !$0.isWhitespace }
        guard !core.isEmpty, !core.allSatisfy({ "嗯啊呃哦唉额哎嘿喂诶噢呀".contains($0) }) else { return }
        let hasChinese = core.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let english = !hasChinese && lang.contains("en")

        DispatchQueue.main.async { self.enqueue(raw, english: english, ended: ended) }
    }

    /// Main thread.
    private func enqueue(_ zh: String, english: Bool, ended: Date) {
        if english && !settings.interpretPassEnglish { return }
        let id = nextID
        nextID += 1
        lines.append(Line(id: id, zh: zh))
        if lines.count > 30 { lines.removeFirst(lines.count - 30) }

        let config = LLMConfig.snapshot()
        let context = lines.dropLast().suffix(3).map { $0.zh }
        let voice = settings.interpretVoice, speed = Float(settings.interpretSpeed)
        let cleaner = self.cleaner
        let translation = Task { () throws -> String in
            if english { return zh }
            return try await cleaner.interpret(zh, context: Array(context), config: config)
        }
        let previous = tail
        tail = Task { @MainActor [weak self] in
            await previous?.value
            let result = await translation.result
            guard let self, let i = self.lines.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case let .success(reply):
                // Anything without Latin letters or digits (a stray "空", a note in Chinese) is not speakable English.
                let en = reply.contains(where: { $0.isASCII && ($0.isLetter || $0.isNumber) }) ? reply : ""
                self.lines[i].en = en
                self.lines[i].ms = Int(Date().timeIntervalSince(ended) * 1000)
                if !en.isEmpty { self.speaker?.say(en, voice: voice, speed: speed) }
            case let .failure(err):
                self.lines[i].failed = true
                self.error = "翻译失败：\(err.localizedDescription)"
            }
        }
    }

    private func refreshPhase() {
        guard phase != .off, phase != .loading else { return }
        phase = speaking ? .speaking : (hearing ? .hearing : .listening)
    }

    private func fail(_ message: String) {
        error = message
        phase = .off
        panel.show()
    }
}

// MARK: - Subtitle panel

/// Floating, draggable window with live subtitles; stays above the meeting app without taking focus.
final class InterpreterPanel {
    private let panel: NSPanel

    init(interpreter: Interpreter) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .resizable],
                        backing: .buffered, defer: true)
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 320, height: 160)
        let host = NSHostingView(rootView: InterpreterView(interpreter: interpreter, onClose: { [weak panel] in panel?.orderOut(nil) }))
        panel.contentView = host
        panel.setFrameAutosaveName("SaycribeInterpreter")
        if panel.frame.origin == .zero, let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 460, y: screen.maxY - 320))
        }
    }

    func show() { panel.orderFrontRegardless() }
}

struct InterpreterView: View {
    @ObservedObject var interpreter: Interpreter
    @ObservedObject private var settings = Settings.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            if let error = interpreter.error {
                notice(error)
            } else if interpreter.isOn && AudioDevices.virtualCable == nil && settings.interpretOutputUID.isEmpty {
                notice("没有找到虚拟麦克风（BlackHole），英文语音暂时从扬声器播放。")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if interpreter.lines.isEmpty {
                            Text(interpreter.isOn ? "开始说中文吧，每说完一句停顿一下，英文就会读出来。" : "在会议软件里把麦克风选成「BlackHole 2ch」，再点上面的开始。")
                                .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.45))
                        }
                        ForEach(interpreter.lines) { line in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(line.zh).font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.5))
                                if line.failed {
                                    Text("翻译失败").font(.system(size: 14)).foregroundStyle(Brand.orange)
                                } else if let en = line.en {
                                    Text(en.isEmpty ? "（跳过）" : en)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(en.isEmpty ? Color.white.opacity(0.35) : Brand.cream)
                                } else {
                                    Text("…").font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.4))
                                }
                            }
                            .textSelection(.enabled)
                            .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .onChange(of: interpreter.lines.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .onChange(of: interpreter.lines.last?.en) { _, _ in
                    if let id = interpreter.lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Brand.ink.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("会议同传 · 中 → EN").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.cream)
                Text(statusText).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            Button(interpreter.isOn ? "停止" : "开始") { interpreter.toggle() }
                .buttonStyle(.borderedProminent)
                .tint(interpreter.isOn ? Color.white.opacity(0.18) : Brand.orange)
                .controlSize(.small)
            Button { if interpreter.isOn { interpreter.stop() }; onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.5))
            .help("停止并关闭")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func notice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Brand.orange)
        .padding(.horizontal, 16).padding(.top, 10)
    }

    private var dotColor: Color {
        switch interpreter.phase {
        case .off: return Color.white.opacity(0.3)
        case .loading: return Color.white.opacity(0.6)
        case .listening: return Color.green.opacity(0.8)
        case .hearing: return Brand.orange
        case .speaking: return Brand.waveTop
        }
    }

    private var statusText: String {
        let out = interpreter.outputName.isEmpty ? "" : " · 输出到 \(interpreter.outputName)"
        switch interpreter.phase {
        case .off: return "已停止"
        case .loading: return "加载模型…"
        case .listening: return "正在听" + out
        case .hearing: return "你在说话…" + out
        case .speaking: return "正在播放英文" + out
        }
    }
}
