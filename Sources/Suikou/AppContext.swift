import AppKit
import ApplicationServices

enum AppStyle: String {
    case chat, email, code, notes

    var label: String {
        switch self {
        case .chat: return "聊天"
        case .email: return "邮件"
        case .code: return "代码"
        case .notes: return "通用"
        }
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
    var style: AppStyle { AppStyle.forBundle(bundleID) }

    static func capture() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        return AppContext(pid: app?.processIdentifier, bundleID: app?.bundleIdentifier, appName: app?.localizedName ?? "", selectedText: selection())
    }

    /// Selected text in the focused element via Accessibility. Apps that don't expose it (some Electron apps) return nil.
    private static func selection() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count < 8000
        else { return nil }
        return text
    }
}
