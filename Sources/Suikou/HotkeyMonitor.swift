import AppKit

enum DictationMode { case dictate, translate }

protocol HotkeyDelegate: AnyObject {
    func hotkeyBegan(mode: DictationMode)
    func hotkeyModeChanged(_ mode: DictationMode)
    func hotkeyLocked()
    func hotkeyEnded()
    func hotkeyCancelled()
}

/// Global dictation hotkey on a single modifier key via a listen-only CGEventTap (needs Input Monitoring).
///
/// How a press starts and ends a recording depends on `RecordMode`:
/// - hybrid: hold ≥ 0.3s then release → end; a quick tap starts hands-free, the next press ends.
/// - hold: hold then release → end; a quick tap is discarded, a double tap starts hands-free.
/// - toggle: one press starts, the next press ends.
/// - Esc while recording → cancel. Any other key while holding → cancel (user was pressing a shortcut like Fn+F1).
/// - Holding ⌘+⌥ (either side, no other modifiers) does the same in translate mode. Adding ⌥ while the
///   dictation key is held upgrades that recording to translate.
final class HotkeyMonitor {
    enum State { case idle, holding, locked }

    weak var delegate: HotkeyDelegate?
    private(set) var state: State = .idle
    private(set) var mode: DictationMode = .dictate
    private var comboHeld = false
    /// Diagnostics: whether the tap is installed and the last modifier key we saw.
    var isActive: Bool { tap != nil }
    private(set) var lastFlagsKeyCode: Int64 = -1
    private(set) var lastFlagsAt: Date?
    private var tap: CFMachPort?
    private var downAt = Date.distantPast
    private var lastTapAt = Date.distantPast

    private let holdThreshold = 0.3
    private let doubleTapWindow = 0.4

    var hotkey: Hotkey { Settings.shared.hotkey }
    var recordMode: RecordMode { Settings.shared.recordMode }

    func start() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                me.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Called by the coordinator when it finishes or aborts on its own.
    func reset() { state = .idle }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // We may have missed the key-up while disabled; don't leave the mic running.
            if state != .idle {
                state = .idle
                notify { $0.hotkeyCancelled() }
            }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            lastFlagsKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
            lastFlagsAt = Date()
            let combo = isTranslateCombo(event.flags)
            if combo != comboHeld {
                comboHeld = combo
                if combo {
                    comboDown()
                    return
                }
                if state == .holding && mode == .translate { keyUp() }
            }
            guard event.getIntegerValueField(.keyboardEventKeycode) == hotkey.keyCode else { return }
            isDown(event.flags) ? keyDown(.dictate) : keyUp()
        case .keyDown:
            guard state != .idle else { return }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == 53 || state == .holding { // Esc, or a shortcut like Fn+F1
                state = .idle
                notify { $0.hotkeyCancelled() }
            }
        default:
            break
        }
    }

    /// Uses device-specific bits for right-hand modifiers so a held left Option/Command doesn't look like ours.
    private func isDown(_ flags: CGEventFlags) -> Bool {
        switch hotkey {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .rightOption: return flags.rawValue & 0x40 != 0 // NX_DEVICERALTKEYMASK
        case .rightCommand: return flags.rawValue & 0x10 != 0 // NX_DEVICERCMDKEYMASK
        }
    }

    private func isTranslateCombo(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) && flags.contains(.maskAlternate)
            && !flags.contains(.maskControl) && !flags.contains(.maskShift)
    }

    private func comboDown() {
        if state == .holding && mode == .dictate {
            mode = .translate
            notify { $0.hotkeyModeChanged(.translate) }
        } else {
            keyDown(.translate)
        }
    }

    /// Delegate work (AX queries, starting the audio engine) runs after the tap callback returns, so the tap never times out.
    private func notify(_ body: @escaping (HotkeyDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let d = self?.delegate { body(d) }
        }
    }

    private func keyDown(_ newMode: DictationMode) {
        switch state {
        case .idle:
            mode = newMode
            downAt = Date()
            notify { $0.hotkeyBegan(mode: newMode) }
            if recordMode == .toggle {
                state = .locked
                notify { $0.hotkeyLocked() }
            } else {
                state = .holding
            }
        case .locked:
            state = .idle
            notify { $0.hotkeyEnded() }
        case .holding:
            break
        }
    }

    private func keyUp() {
        guard state == .holding else { return }
        let now = Date()
        if now.timeIntervalSince(downAt) >= holdThreshold {
            state = .idle
            notify { $0.hotkeyEnded() }
        } else if recordMode == .hybrid {
            state = .locked
            notify { $0.hotkeyLocked() }
        } else if now.timeIntervalSince(lastTapAt) <= doubleTapWindow {
            state = .locked
            lastTapAt = .distantPast
            notify { $0.hotkeyLocked() }
        } else {
            state = .idle
            lastTapAt = now
            notify { $0.hotkeyCancelled() }
        }
    }
}
