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

    var hotkey: HotkeySpec { Settings.shared.hotkey }
    /// The spec the tap was created for (key combos need a filtering tap so the keystroke doesn't reach the app).
    private var tapSpec: HotkeySpec?
    private var comboKeyDown = false
    var recordMode: RecordMode { Settings.shared.recordMode }

    /// Marks events we synthesize (⌘V/⌘C) so our own tap ignores them.
    /// Set while the settings page records a new hotkey.
    static var suspended = false
    static let syntheticMarker: Int64 = 0x5359_4352

    /// True when the tap exists and macOS hasn't disabled it.
    var isHealthy: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    private var source: CFRunLoopSource?

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        comboKeyDown = false
        if state != .idle {
            state = .idle
            notify { $0.hotkeyCancelled() }
        }
    }

    /// Tear down and recreate the tap (after permissions come back, a stale tap gets no events).
    @discardableResult
    func restart() -> Bool {
        stop()
        return start()
    }

    func start() -> Bool {
        if tap != nil { return true }
        let spec = hotkey
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: spec.modifierOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }
        self.tap = tap
        tapSpec = spec
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Called by the coordinator when it finishes or aborts on its own.
    func reset() { state = .idle }

    /// Returns true to swallow the event (only possible for key-combo hotkeys, which use a filtering tap).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return false }
        if Self.suspended { return false }
        let spec = tapSpec ?? hotkey
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // We may have missed the key-up while disabled; don't leave the mic running.
            if state != .idle {
                state = .idle
                notify { $0.hotkeyCancelled() }
            }
            comboKeyDown = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            lastFlagsKeyCode = code
            lastFlagsAt = Date()
            let combo = Settings.shared.translateCombo.matches(event.flags)
            if combo != comboHeld {
                comboHeld = combo
                if combo {
                    comboDown()
                    return false
                }
                if state == .holding && mode == .translate { keyUp() }
            }
            guard spec.modifierOnly, code == spec.keyCode else { return false }
            spec.isDown(event.flags) ? keyDown(.dictate) : keyUp()
        case .keyDown:
            if spec.matches(keyCode: code, flags: event.flags) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 && !comboKeyDown {
                    comboKeyDown = true
                    keyDown(.dictate)
                }
                return true
            }
            guard state != .idle else { return false }
            if code == 53 || state == .holding { // Esc, or a shortcut like Fn+F1
                state = .idle
                comboKeyDown = false
                notify { $0.hotkeyCancelled() }
            }
        case .keyUp:
            if !spec.modifierOnly && code == spec.keyCode && comboKeyDown {
                comboKeyDown = false
                keyUp()
                return true
            }
        default:
            break
        }
        return false
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
