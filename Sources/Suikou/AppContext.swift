import AppKit
import ApplicationServices

enum AppStyle: String, CaseIterable {
    case chat, email, code, notes

    var label: String {
        switch self {
        case .chat: return "聊天"
        case .email: return "邮件"
        case .code: return "代码"
        case .notes: return "通用"
        }
    }

    /// A user override (exact bundle id, case-insensitive) wins over the built-in guess.
    static func resolve(_ id: String?, overrides: [String: String]) -> AppStyle {
        if let id, let raw = overrides.first(where: { $0.key.lowercased() == id.lowercased() })?.value,
           let s = AppStyle(rawValue: raw) { return s }
        return forBundle(id)
    }

    static func forBundle(_ id: String?) -> AppStyle {
        guard let id = id?.lowercased() else { return .notes }
        let chat = ["xinwechat", "com.tencent.qq", "slack", "lark", "feishu", "telegram", "discord", "whatsapp",
                    "mobilesms", "dingtalk", "wework", "messenger", "naver.line"]
        let email = ["com.apple.mail", "outlook", "spark", "smartemail", "airmail", "mimestream", "microsoft.word", "iwork.pages"]
        let code = ["vscode", "todesktop", "cursor", "terminal", "iterm", "warp", "jetbrains", "xcode", "zed", "ghostty",
                    "sublime", "kitty", "alacritty", "claudefordesktop", "openai.chat", "codex"]
        if code.contains(where: id.contains) { return .code }
        if chat.contains(where: id.contains) { return .chat }
        if email.contains(where: id.contains) { return .email }
        return .notes
    }
}

/// Snapshot of where the text will go, taken the moment the hotkey goes down.
struct AppContext {
    let pid: pid_t?
    let bundleID: String?
    let appName: String
    let selectedText: String?
    /// Resolved on the main thread at capture, so background work never reads live Settings.
    let style: AppStyle

    static func capture() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        return AppContext(pid: app?.processIdentifier, bundleID: app?.bundleIdentifier, appName: app?.localizedName ?? "", selectedText: selection(),
                          style: AppStyle.resolve(app?.bundleIdentifier, overrides: Settings.shared.styleOverrides))
    }

    enum AXSelection: Equatable { case text(String), empty, unsupported }

    /// Whether to try ⌘C: only when the app doesn't expose a selection at all (AX said nothing, not "empty").
    static func needsCopyFallback(_ ax: AXSelection, enabled: Bool) -> Bool { enabled && ax == .unsupported }

    /// Selected text in the focused element via Accessibility, falling back to ⌘C for apps (Electron) that hide it.
    private static func selection() -> String? {
        let ax = axSelection()
        if case let .text(t) = ax { return t }
        return needsCopyFallback(ax, enabled: Settings.shared.copySelectionFallback) ? Inserter.copySelectionViaCommandC() : nil
    }

    private static func axSelection() -> AXSelection {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return .unsupported }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String
        else { return .unsupported }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || text.count >= 8000 ? .empty : .text(text)
    }
}
