import Foundation
import ServiceManagement

enum Hotkey: String, CaseIterable, Identifiable {
    case fn, rightOption, rightCommand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: return "Fn（🌐）"
        case .rightOption: return "右 Option"
        case .rightCommand: return "右 Command"
        }
    }

    var keycap: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "右 ⌥"
        case .rightCommand: return "右 ⌘"
        }
    }

    /// Virtual key code reported in flagsChanged events.
    var keyCode: Int64 {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        }
    }
}

/// User preferences, persisted in UserDefaults. The API key lives in ~/.config/suikou/secrets.env (chmod 600).
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var hotkey: Hotkey { didSet { d.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var llmEnabled: Bool { didSet { d.set(llmEnabled, forKey: "llmEnabled") } }
    @Published var cleanModel: String { didSet { d.set(cleanModel, forKey: "cleanModel") } }
    @Published var editModel: String { didSet { d.set(editModel, forKey: "editModel") } }
    @Published var asrLanguage: String { didSet { d.set(asrLanguage, forKey: "asrLanguage") } }
    @Published var dictionaryText: String { didSet { d.set(dictionaryText, forKey: "dictionary") } }
    @Published var apiKey: String { didSet { Self.saveKey(apiKey) } }
    /// CoreAudio UID of the chosen microphone; empty = follow the system default.
    @Published var micUID: String { didSet { d.set(micUID, forKey: "micUID") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }
    /// Leave the dictated text on the clipboard instead of restoring what was there before.
    @Published var keepInClipboard: Bool { didSet { d.set(keepInClipboard, forKey: "keepInClipboard") } }
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
    /// Utterances of at most `shortSentenceLimit` words are cleaned on-device instead of calling DeepSeek.
    @Published var skipShortSentences: Bool { didSet { d.set(skipShortSentences, forKey: "skipShortSentences") } }
    @Published var shortSentenceLimit: Int { didSet { d.set(shortSentenceLimit, forKey: "shortSentenceLimit") } }
    static let shortSentenceLimits = [6, 12, 20, 30]

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
        hotkey = Hotkey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .fn
        llmEnabled = d.object(forKey: "llmEnabled") as? Bool ?? true
        cleanModel = d.string(forKey: "cleanModel") ?? "deepseek-flash"
        editModel = d.string(forKey: "editModel") ?? "deepseek-flash"
        asrLanguage = d.string(forKey: "asrLanguage") ?? "auto"
        dictionaryText = d.string(forKey: "dictionary") ?? ""
        apiKey = Self.loadKey()
        micUID = d.string(forKey: "micUID") ?? ""
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        keepInClipboard = d.bool(forKey: "keepInClipboard")
        showInDock = d.bool(forKey: "showInDock")
        translateTarget = d.string(forKey: "translateTarget") ?? "en"
        skipShortSentences = d.object(forKey: "skipShortSentences") as? Bool ?? true
        shortSentenceLimit = d.object(forKey: "shortSentenceLimit") as? Int ?? 12
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - API key file

    static let secretsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/suikou/secrets.env")

    private static func loadKey() -> String {
        guard let text = try? String(contentsOf: secretsURL, encoding: .utf8) else { return "" }
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("DEEPSEEK_API_KEY=") {
            return String(line.dropFirst("DEEPSEEK_API_KEY=".count)).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    private static func saveKey(_ key: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: secretsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "DEEPSEEK_API_KEY=\(key)\n".write(to: secretsURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
    }
}
