import AppKit

/// A user-chosen dictation trigger: either one modifier key on its own (fn, right ⌘ …) or a key with modifiers (⌃Space, F5 …).
struct HotkeySpec: Codable, Hashable {
    var keyCode: Int64
    /// Required modifiers for key combos (CGEventFlags raw bits of ⌘⌥⌃⇧ only). Ignored for modifier-only keys.
    var modifiers: UInt64 = 0
    var modifierOnly: Bool

    static let modMask: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue

    /// keyCode → (device-specific flag bit, label). fn uses the secondary-fn flag.
    static let modifierKeys: [Int64: (bit: UInt64, label: String)] = [
        54: (0x10, "右 ⌘"), 55: (0x08, "左 ⌘"), 61: (0x40, "右 ⌥"), 58: (0x20, "左 ⌥"),
        62: (0x2000, "右 ⌃"), 59: (0x01, "左 ⌃"), 60: (0x04, "右 ⇧"), 56: (0x02, "左 ⇧"),
        63: (CGEventFlags.maskSecondaryFn.rawValue, "fn"),
    ]

    static let fn = HotkeySpec(keyCode: 63, modifierOnly: true)
    static let presets: [(String, HotkeySpec)] = [
        ("Fn（🌐）", .fn), ("右 Option", HotkeySpec(keyCode: 61, modifierOnly: true)),
        ("右 Command", HotkeySpec(keyCode: 54, modifierOnly: true)),
    ]

    /// Old settings stored a preset name.
    static func legacy(_ name: String?) -> HotkeySpec? {
        switch name {
        case "fn": return .fn
        case "rightOption": return HotkeySpec(keyCode: 61, modifierOnly: true)
        case "rightCommand": return HotkeySpec(keyCode: 54, modifierOnly: true)
        default: return nil
        }
    }

    /// For modifier-only keys: is our key currently down?
    func isDown(_ flags: CGEventFlags) -> Bool {
        guard let bit = Self.modifierKeys[keyCode]?.bit else { return false }
        return flags.rawValue & bit != 0
    }

    /// For key combos: does this keyDown/keyUp event match (exact modifiers, fn/caps ignored)?
    func matches(keyCode code: Int64, flags: CGEventFlags) -> Bool {
        !modifierOnly && code == keyCode && flags.rawValue & Self.modMask == modifiers
    }

    var keycap: String {
        if modifierOnly { return Self.modifierKeys[keyCode]?.label ?? "键 \(keyCode)" }
        var s = ""
        let f = CGEventFlags(rawValue: modifiers)
        if f.contains(.maskControl) { s += "⌃" }
        if f.contains(.maskAlternate) { s += "⌥" }
        if f.contains(.maskShift) { s += "⇧" }
        if f.contains(.maskCommand) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    var label: String { Self.presets.first { $0.1 == self }?.0 ?? keycap }

    static let functionKeys: [Int64: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]
    static let namedKeys: [Int64: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 50: "`", 123: "←", 124: "→", 125: "↓", 126: "↑"]
    static let letters: [Int64: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\",
    ]

    static func keyName(_ code: Int64) -> String {
        functionKeys[code] ?? namedKeys[code] ?? letters[code] ?? "键\(code)"
    }

    /// Why a recorded combo can't be used, or nil if it's fine.
    static func problem(_ spec: HotkeySpec) -> String? {
        if spec.modifierOnly { return modifierKeys[spec.keyCode] == nil ? "不支持这个键" : nil }
        if spec.keyCode == 53 { return "Esc 用来取消，不能当说话键" }
        let isF = functionKeys[spec.keyCode] != nil
        if spec.modifiers == 0 && !isF { return "单个普通键会影响打字，请加上 ⌃/⌥/⌘ 或用 F 键" }
        if spec.modifiers == CGEventFlags.maskShift.rawValue && !isF { return "只加 ⇧ 会和打大写冲突，请换一个" }
        let reserved: Set<String> = ["⌘C", "⌘V", "⌘X", "⌘Z", "⌘A", "⌘Q", "⌘W", "⌘Space", "⌃Space", "⌘⇥"]
        if reserved.contains(spec.keycap) { return "\(spec.keycap) 是系统常用快捷键，请换一个" }
        return nil
    }
}

/// Which pair of modifiers held together starts a translation.
enum TranslateCombo: String, CaseIterable, Identifiable {
    case cmdOpt, ctrlOpt, ctrlCmd, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cmdOpt: return "⌘ + ⌥"
        case .ctrlOpt: return "⌃ + ⌥"
        case .ctrlCmd: return "⌃ + ⌘"
        case .off: return "不用翻译键"
        }
    }
    var keys: [String] {
        switch self {
        case .cmdOpt: return ["⌘", "⌥"]
        case .ctrlOpt: return ["⌃", "⌥"]
        case .ctrlCmd: return ["⌃", "⌘"]
        case .off: return []
        }
    }

    /// Exactly these two modifiers (either side), nothing else from ⌘⌥⌃⇧.
    func matches(_ flags: CGEventFlags) -> Bool {
        let want: CGEventFlags
        switch self {
        case .cmdOpt: want = [.maskCommand, .maskAlternate]
        case .ctrlOpt: want = [.maskControl, .maskAlternate]
        case .ctrlCmd: want = [.maskControl, .maskCommand]
        case .off: return false
        }
        return flags.rawValue & HotkeySpec.modMask == want.rawValue
    }
}

/// Records the next key the user presses in our own window: a lone modifier tap, or a key with modifiers.
final class HotkeyRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var message: String?
    private var monitor: Any?
    private var pendingModifier: Int64?
    var onRecorded: ((HotkeySpec) -> Void)?

    func start() {
        stop()
        isRecording = true
        message = "请按下新的说话键…（Esc 取消）"
        HotkeyMonitor.suspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        pendingModifier = nil
        HotkeyMonitor.suspended = false
    }

    private func handle(_ event: NSEvent) {
        let code = Int64(event.keyCode)
        if event.type == .flagsChanged {
            guard HotkeySpec.modifierKeys[code] != nil else { return }
            let spec = HotkeySpec(keyCode: code, modifierOnly: true)
            if spec.isDown(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))) {
                pendingModifier = code
            } else if pendingModifier == code {
                finish(spec) // pressed and released alone
            }
            return
        }
        pendingModifier = nil
        if code == 53 && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            message = nil; stop(); return
        }
        let mods = UInt64(event.modifierFlags.rawValue) & HotkeySpec.modMask
        finish(HotkeySpec(keyCode: code, modifiers: mods, modifierOnly: false))
    }

    private func finish(_ spec: HotkeySpec) {
        if let problem = HotkeySpec.problem(spec) { message = problem; return } // keep listening
        message = nil
        stop()
        onRecorded?(spec)
    }
}
