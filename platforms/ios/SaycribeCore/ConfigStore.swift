import Foundation

/// 非敏感配置，存放在 App Group 的 UserDefaults 里，主 App 和键盘都能读。
public final class ConfigStore {
    public enum Key: String {
        case relayBaseURL = "relay.baseURL"
        case style = "clean.style"
        case dictionary = "clean.dictionary"
        case modelURL = "model.url"
        case modelSHA256 = "model.sha256"
        case modelSize = "model.size"
        case onboardingDone = "onboarding.done"
    }

    public static let shared = ConfigStore()
    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: SharedConstants.appGroupID) ?? .standard
    }

    /// 中转地址：可配置，非法值回退默认地址。
    public var relayBaseURL: URL {
        get {
            guard let s = defaults.string(forKey: Key.relayBaseURL.rawValue),
                  let url = ConfigStore.normalizedURL(s) else { return SharedConstants.defaultRelayBaseURL }
            return url
        }
        set { defaults.set(newValue.absoluteString, forKey: Key.relayBaseURL.rawValue) }
    }

    /// 校验用户输入的地址，只接受 http/https，去掉尾部斜杠。
    public static func normalizedURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return nil }
        return url
    }

    public var style: String {
        get { defaults.string(forKey: Key.style.rawValue) ?? "notes" }
        set { defaults.set(newValue, forKey: Key.style.rawValue) }
    }

    public var dictionary: [String] {
        get { defaults.stringArray(forKey: Key.dictionary.rawValue) ?? [] }
        set { defaults.set(newValue, forKey: Key.dictionary.rawValue) }
    }

    /// 模型下载地址等，最终取值以 docs/模型下载.md 为准。
    public var modelURL: URL? {
        get { defaults.string(forKey: Key.modelURL.rawValue).flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: Key.modelURL.rawValue) }
    }

    public var modelSHA256: String? {
        get { defaults.string(forKey: Key.modelSHA256.rawValue) }
        set { defaults.set(newValue, forKey: Key.modelSHA256.rawValue) }
    }

    public var onboardingDone: Bool {
        get { defaults.bool(forKey: Key.onboardingDone.rawValue) }
        set { defaults.set(newValue, forKey: Key.onboardingDone.rawValue) }
    }
}
