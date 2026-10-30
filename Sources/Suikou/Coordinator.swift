import AppKit

/// Runs one dictation: hotkey → record → recognize → clean/edit → insert.
final class Coordinator: HotkeyDelegate {
    let hotkeys = HotkeyMonitor()
    let hud = HUDController()
    let history = History()
    let stats = Stats()

    private let recorder = AudioRecorder()
    private let cleaner: Cleaner
    private let modelDir: URL
    private var recognizer: Recognizer?
    private var context: AppContext?
    private var mode: DictationMode = .dictate
    /// HUD and start sound wait a beat, so ⌘⌥-shortcuts (which cancel on the next key) don't flash the pill.
    private var revealWork: DispatchWorkItem?
    private var revealed = false
    private var pendingEditing = false
    private var pendingTranslateLabel: String?
    private var llmConfig = LLMConfig.snapshot()
    private var isProcessing = false
    private let asrQueue = DispatchQueue(label: "suikou.asr", qos: .userInitiated)
    private let settings = Settings.shared

    var isModelReady: Bool { recognizer != nil }

    private(set) lazy var interpreter: Interpreter = {
        let i = Interpreter(resources: resources, cleaner: cleaner, recognizer: { [weak self] in self?.recognizer })
        Interpreter.shared = i
        return i
    }()
    private let resources: URL

    init(resources: URL) {
        self.resources = resources
        cleaner = Cleaner(resources: resources)
        modelDir = resources.appendingPathComponent("models/sense-voice")
        hotkeys.delegate = self
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.hud.model.meter.push(rms: level) }
        }
        hud.model.onCancel = { [weak self] in
            self?.hotkeys.reset()
            self?.hotkeyCancelled()
        }
        hud.model.onFinish = { [weak self] in
            self?.hotkeys.reset()
            self?.hotkeyEnded()
        }
    }

    func loadRecognizer() {
        let dir = modelDir, lang = settings.asrLanguage
        asrQueue.async {
            let r = Recognizer(modelDir: dir, language: lang)
            DispatchQueue.main.async { self.recognizer = r }
        }
    }

    // MARK: - HotkeyDelegate

    func hotkeyBegan(mode: DictationMode) {
        // One dictation at a time: overlapping runs would paste out of order and clobber the saved clipboard.
        guard !isProcessing else { hotkeys.reset(); return }
        let ctx = AppContext.capture()
        context = ctx
        llmConfig = .snapshot()
        self.mode = mode
        do {
            try recorder.start()
        } catch {
            hotkeys.reset()
            flash(.error("麦克风不可用：\(error.localizedDescription)"))
            return
        }
        cleaner.warmUp(apiKey: llmConfig.apiKey)
        pendingEditing = mode == .dictate && ctx.selectedText != nil
        pendingTranslateLabel = mode == .translate ? settings.currentTranslateTarget.short : nil
        revealed = false
        let reveal = DispatchWorkItem { [weak self] in self?.revealNow() }
        revealWork = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: reveal)
    }

    private func revealNow() {
        guard !revealed, recorder.isRunning else { return }
        revealed = true
        Sounds.play(.start)
        hud.show(.listening, editing: pendingEditing, translate: .some(pendingTranslateLabel))
    }

    func hotkeyModeChanged(_ mode: DictationMode) {
        guard recorder.isRunning else { return }
        self.mode = mode
        pendingEditing = false
        pendingTranslateLabel = settings.currentTranslateTarget.short
        if revealed {
            hud.model.editing = false
            hud.model.translateLabel = pendingTranslateLabel
        }
    }

    func hotkeyLocked() {
        revealNow()
        hud.show(.locked)
    }

    func hotkeyCancelled() {
        guard recorder.isRunning else { return } // press was rejected while a previous run is processing
        revealWork?.cancel()
        recorder.stop()
        hud.hide()
    }

    func hotkeyEnded() {
        guard recorder.isRunning else { return }
        let samples = recorder.stop()
        revealWork?.cancel()
        Sounds.play(.stop)
        guard let ctx = context, samples.count > Int(AudioRecorder.sampleRate * 0.4) else { hud.hide(); return }
        guard let recognizer else { flash(.error("语音模型还在加载，请稍候")); return }
        hud.show(.thinking)
        isProcessing = true
        let started = Date()
        let config = llmConfig, llmEnabled = settings.llmEnabled
        let skipShort = settings.skipShortSentences, shortLimit = settings.shortSentenceLimit
        let audioSeconds = Double(samples.count) / AudioRecorder.sampleRate
        let mode = self.mode, target = settings.currentTranslateTarget

        Task {
            let raw: String = await withCheckedContinuation { cont in
                asrQueue.async { cont.resume(returning: recognizer.transcribe(samples)) }
            }
            guard !raw.isEmpty else { await MainActor.run { finish(.error("没听清，再说一次")) }; return }

            var text = raw
            var warning: String?
            var handledLocally = false
            if mode == .translate {
                do {
                    text = try await cleaner.translate(raw, direction: target.instruction, style: ctx.style, config: config)
                } catch {
                    await MainActor.run {
                        Inserter.copy(raw)
                        finish(.error("翻译失败，原文已复制"), for: 2.5)
                    }
                    return
                }
            } else if let selection = ctx.selectedText {
                do {
                    text = try await cleaner.edit(selection: selection, instruction: raw, config: config)
                } catch {
                    // Never replace the user's selection with the spoken instruction itself.
                    await MainActor.run { finish(.error("改写失败：\(error.localizedDescription)")) }
                    return
                }
            } else if llmEnabled && !(skipShort && Stats.count(raw) <= shortLimit) {
                do {
                    text = try await cleaner.clean(raw, style: ctx.style, config: config)
                } catch {
                    text = LocalCleaner.clean(raw, style: ctx.style)
                    warning = "未整理（\(error.localizedDescription)）"
                }
            } else {
                // Short sentence (or AI cleanup off): tidy it on-device and skip the API round trip.
                text = LocalCleaner.clean(raw, style: ctx.style)
                handledLocally = true
            }
            let finalText = text, finalWarning = warning, local = handledLocally
            let ms = Int(Date().timeIntervalSince(started) * 1000)

            await MainActor.run {
                guard !finalText.isEmpty else { finish(nil); return }
                history.add(HistoryEntry(date: Date(), app: ctx.appName, raw: raw, text: finalText, ms: ms, audioSeconds: audioSeconds,
                                         mode: mode == .translate ? "translate:\(target.id)" : (local ? "local" : nil)))
                stats.record(text: finalText, audioSeconds: audioSeconds)

                // Paste only into the window the user was talking to, and only if we're allowed to send keystrokes.
                let sameTarget = ctx.pid == nil || NSWorkspace.shared.frontmostApplication?.processIdentifier == ctx.pid
                guard Permissions.accessibility, sameTarget else {
                    Inserter.copy(finalText)
                    finish(.error(Permissions.accessibility ? "窗口已切换，结果已复制" : "未开启辅助功能，结果已复制"), for: 2.5)
                    return
                }
                Inserter.insert(finalText, restoreClipboard: !settings.keepInClipboard)
                if let finalWarning {
                    finish(.error(finalWarning), for: 2.5)
                } else {
                    finish(.done, for: 0.7)
                }
            }
        }
    }

    private func finish(_ phase: HUDModel.Phase?, for seconds: TimeInterval = 1.6) {
        isProcessing = false
        if let phase { flash(phase, for: seconds) } else { hud.hide() }
    }

    private func flash(_ phase: HUDModel.Phase, for seconds: TimeInterval = 1.6) {
        hud.show(phase)
        hud.hide(after: seconds)
    }
}

/// Short, quiet cues when recording starts and stops.
enum Sounds {
    enum Cue { case start, stop }

    private static let start: NSSound? = {
        let s = NSSound(named: "Tink")
        s?.volume = 0.25
        return s
    }()
    private static let stop: NSSound? = {
        let s = NSSound(named: "Pop")
        s?.volume = 0.25
        return s
    }()

    static func play(_ cue: Cue) {
        guard Settings.shared.playSounds else { return }
        let sound = cue == .start ? start : stop
        sound?.stop()
        sound?.play()
    }
}
