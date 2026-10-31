import Foundation
import ServiceManagement

enum RecordMode: String, CaseIterable, Identifiable {
    case hybrid, hold, toggle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hybrid: return "按住说话 + 点一下开始"
        case .hold: return "只用按住说话"
        case .toggle: return "点一下开始，再点一下结束"
        }
    }

    var hint: String {
        switch self {
        case .hybrid: return "按住超过 0.3 秒是按住说话，松开就写入；快速点一下开始收听，说完再点一下结束。"
        case .hold: return "按住说话，松开就写入；快速双击可以锁定收听。"
        case .toggle: return "点一下开始收听，说完再点一下结束。不用一直按着。"
        }
    }

    /// Rest of the home-page hint after "按住/点一下 [key]".
    var homeTail: String {
        switch self {
        case .hybrid: return "说话，松开即写入；也可以点一下开始、再点一下结束。"
        case .hold: return "说话，松开即写入。"
        case .toggle: return "开始说话，再点一下结束并写入。"
        }
    }
}

/// User preferences, persisted in UserDefaults. The relay device token lives in the keychain; base URL is configurable.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var hotkey: HotkeySpec { didSet { d.set(try? JSONEncoder().encode(hotkey), forKey: "hotkeySpec") } }
    @Published var translateCombo: TranslateCombo { didSet { d.set(translateCombo.rawValue, forKey: "translateCombo") } }
    @Published var recordMode: RecordMode { didSet { d.set(recordMode.rawValue, forKey: "recordMode") } }
    @Published var llmEnabled: Bool { didSet { d.set(llmEnabled, forKey: "llmEnabled") } }
    @Published var cleanModel: String { didSet { d.set(cleanModel, forKey: "cleanModel") } }
    @Published var editModel: String { didSet { d.set(editModel, forKey: "editModel") } }
    @Published var asrLanguage: String { didSet { d.set(asrLanguage, forKey: "asrLanguage") } }
    /// bundle id → AppStyle raw value, set on the settings page; beats AppStyle.forBundle.
    @Published var styleOverrides: [String: String] { didSet { d.set(styleOverrides, forKey: "styleOverrides") } }
    @Published var dictionaryText: String { didSet { d.set(dictionaryText, forKey: "dictionary") } }
    /// Saycribe relay base URL (no trailing slash). Default from docs / .relay-tokens.env.
    @Published var relayBaseURL: String { didSet { d.set(relayBaseURL, forKey: "relayBaseURL") } }
    /// Device token `sct_…` stored in the keychain — never logged.
    @Published var relayToken: String { didSet { KeychainStore.save(relayToken) } }
    /// CoreAudio UID of the chosen microphone; empty = follow the system default.
    @Published var micUID: String { didSet { d.set(micUID, forKey: "micUID") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }
    /// Leave the dictated text on the clipboard instead of restoring what was there before.
    @Published var keepInClipboard: Bool { didSet { d.set(keepInClipboard, forKey: "keepInClipboard") } }
    /// Seconds to wait after ⌘V before putting the old clipboard back (slow apps need longer).
    @Published var clipboardRestoreDelay: Double { didSet { d.set(clipboardRestoreDelay, forKey: "clipboardRestoreDelay") } }
    /// Read the selection with ⌘C when the app's Accessibility tree hides it (Electron apps).
    @Published var copySelectionFallback: Bool { didSet { d.set(copySelectionFallback, forKey: "copySelectionFallback") } }
    /// Off: dictations aren't written to history at all.
    @Published var saveHistory: Bool { didSet { d.set(saveHistory, forKey: "saveHistory") } }
    /// 0 = keep (up to the entry limit).
    @Published var historyRetentionDays: Int { didSet { d.set(historyRetentionDays, forKey: "historyRetentionDays") } }
    static let retentionChoices: [(Int, String)] = [(1, "1 天"), (7, "7 天"), (30, "30 天"), (90, "90 天"), (0, "一直保留")]
    @Published var hasCompletedOnboarding: Bool { didSet { d.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    @Published var showInDock: Bool { didSet { d.set(showInDock, forKey: "showInDock") } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Suikou: launch at login failed: \(error)")
            }
        }
    }

    @Published var translateTarget: String { didSet { d.set(translateTarget, forKey: "translateTarget") } }
    /// Kept for prefs migration; short utterances now always go through the relay (non-streaming).
    @Published var skipShortSentences: Bool { didSet { d.set(skipShortSentences, forKey: "skipShortSentences") } }
    @Published var shortSentenceLimit: Int { didSet { d.set(shortSentenceLimit, forKey: "shortSentenceLimit") } }
    static let shortSentenceLimits = [6, 12, 20, 30]

    /// Meeting interpreter: where the English voice goes (CoreAudio UID; empty = the virtual cable if installed).
    @Published var interpretOutputUID: String { didSet { d.set(interpretOutputUID, forKey: "interpretOutputUID") } }
    /// Kokoro speaker id, see Speaker.voices.
    @Published var interpretVoice: Int { didSet { d.set(interpretVoice, forKey: "interpretVoice") } }
    @Published var interpretSpeed: Double { didSet { d.set(interpretSpeed, forKey: "interpretSpeed") } }
    /// Voice English sentences as they are instead of dropping them (off: they're usually other people's audio leaking in).
    @Published var interpretPassEnglish: Bool { didSet { d.set(interpretPassEnglish, forKey: "interpretPassEnglish") } }
    static let interpretSpeeds: [(Double, String)] = [(0.9, "慢"), (1.0, "正常"), (1.1, "稍快"), (1.25, "快")]

    struct TranslateTarget: Identifiable {
        let id: String
        let name: String
        /// Shown on the recording pill.
        let short: String
        /// Sent to the model as 【翻译方向】.
        let instruction: String
    }

    static let translateTargets: [TranslateTarget] = [
        .init(id: "en", name: "英语", short: "EN", instruction: "把原话翻译成英文（English）。"),
        .init(id: "zh-en", name: "中英互译", short: "中⇄EN", instruction: "如果原话主要是中文，翻译成英文；如果主要是英文或其他语言，翻译成简体中文。"),
        .init(id: "zh", name: "简体中文", short: "中", instruction: "把原话翻译成简体中文。"),
        .init(id: "ja", name: "日语", short: "日", instruction: "把原话翻译成日文（日本語）。"),
        .init(id: "ko", name: "韩语", short: "韩", instruction: "把原话翻译成韩文（한국어）。"),
        .init(id: "fr", name: "法语", short: "FR", instruction: "把原话翻译成法文（Français）。"),
        .init(id: "de", name: "德语", short: "DE", instruction: "把原话翻译成德文（Deutsch）。"),
        .init(id: "es", name: "西班牙语", short: "ES", instruction: "把原话翻译成西班牙文（Español）。"),
    ]

    var currentTranslateTarget: TranslateTarget {
        Self.translateTargets.first { $0.id == translateTarget } ?? Self.translateTargets[0]
    }

    static let models = ["deepseek-flash", "deepseek-v4-pro"]
    static let languages = [("auto", "自动"), ("zh", "普通话"), ("en", "English"), ("yue", "粤语")]

    var dictionary: [String] {
        dictionaryText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private init() {
        hotkey = d.data(forKey: "hotkeySpec").flatMap { try? JSONDecoder().decode(HotkeySpec.self, from: $0) }
            ?? HotkeySpec.legacy(d.string(forKey: "hotkey")) ?? .fn
        translateCombo = TranslateCombo(rawValue: d.string(forKey: "translateCombo") ?? "") ?? .cmdOpt
        recordMode = RecordMode(rawValue: d.string(forKey: "recordMode") ?? "") ?? .hybrid
        llmEnabled = d.object(forKey: "llmEnabled") as? Bool ?? true
        cleanModel = d.string(forKey: "cleanModel") ?? "deepseek-flash"
        editModel = d.string(forKey: "editModel") ?? "deepseek-flash"
        asrLanguage = d.string(forKey: "asrLanguage") ?? "auto"
        styleOverrides = d.dictionary(forKey: "styleOverrides") as? [String: String] ?? [:]
        dictionaryText = d.string(forKey: "dictionary") ?? ""
        relayBaseURL = d.string(forKey: "relayBaseURL") ?? ""
        relayToken = KeychainStore.load()
        micUID = d.string(forKey: "micUID") ?? ""
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        keepInClipboard = d.bool(forKey: "keepInClipboard")
        hasCompletedOnboarding = d.bool(forKey: "hasCompletedOnboarding")
        showInDock = d.bool(forKey: "showInDock")
        saveHistory = d.object(forKey: "saveHistory") as? Bool ?? true
        historyRetentionDays = d.object(forKey: "historyRetentionDays") as? Int ?? 0
        clipboardRestoreDelay = Inserter.clampDelay(d.object(forKey: "clipboardRestoreDelay") as? Double ?? 0.8)
        copySelectionFallback = d.object(forKey: "copySelectionFallback") as? Bool ?? true
        translateTarget = d.string(forKey: "translateTarget") ?? "en"
        skipShortSentences = d.object(forKey: "skipShortSentences") as? Bool ?? true
        shortSentenceLimit = d.object(forKey: "shortSentenceLimit") as? Int ?? 12
        interpretOutputUID = d.string(forKey: "interpretOutputUID") ?? ""
        interpretVoice = d.object(forKey: "interpretVoice") as? Int ?? 6
        interpretSpeed = d.object(forKey: "interpretSpeed") as? Double ?? 1.0
        interpretPassEnglish = d.bool(forKey: "interpretPassEnglish")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        // Fill empty relay URL/token from the gitignored env file (dev / first run).
        RelayBootstrap.applyIfNeeded(to: self)
        if relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            relayBaseURL = RelayBootstrap.defaultBaseURL
        }
    }

    // MARK: - Relay bootstrap

    /// Import URL/token from platforms/mac/.relay-tokens.env when keychain/URL are empty.
    func ensureRelayConfigured() {
        RelayBootstrap.applyIfNeeded(to: self)
        if relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            relayBaseURL = RelayBootstrap.defaultBaseURL
        }
    }
}
