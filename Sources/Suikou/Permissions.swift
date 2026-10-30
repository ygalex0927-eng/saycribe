import AppKit
import ApplicationServices
import AVFoundation

enum Permissions {
    static var microphone: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }
    static var allGranted: Bool { microphone && accessibility && inputMonitoring }

    static func open(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

struct PermissionSnapshot: Equatable {
    var microphone: Bool
    var accessibility: Bool
    var inputMonitoring: Bool

    static var current: PermissionSnapshot {
        PermissionSnapshot(microphone: Permissions.microphone, accessibility: Permissions.accessibility,
                           inputMonitoring: Permissions.inputMonitoring)
    }

    enum Kind: String { case microphone = "麦克风", accessibility = "辅助功能", inputMonitoring = "输入监控" }
    enum Change: Equatable { case lost(Kind), regained(Kind) }

    /// What changed between two polls (lost = was granted, now isn't).
    static func diff(_ old: PermissionSnapshot, _ new: PermissionSnapshot) -> [Change] {
        var out: [Change] = []
        let pairs: [(Kind, Bool, Bool)] = [(.microphone, old.microphone, new.microphone),
                                          (.accessibility, old.accessibility, new.accessibility),
                                          (.inputMonitoring, old.inputMonitoring, new.inputMonitoring)]
        for (k, a, b) in pairs where a != b { out.append(b ? .regained(k) : .lost(k)) }
        return out
    }

    var missing: [Kind] {
        var out: [Kind] = []
        if !microphone { out.append(.microphone) }
        if !accessibility { out.append(.accessibility) }
        if !inputMonitoring { out.append(.inputMonitoring) }
        return out
    }
}

/// Polls permissions; reports changes and keeps the hotkey tap alive (macOS silently kills it when
/// Input Monitoring / Accessibility is revoked, e.g. after an app update re-signs the binary).
final class PermissionWatcher {
    private var last = PermissionSnapshot.current
    private var timer: Timer?
    var onChange: (([PermissionSnapshot.Change], PermissionSnapshot) -> Void)?
    var onTick: ((PermissionSnapshot) -> Void)?

    func start(interval: TimeInterval = 2) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
        let now = PermissionSnapshot.current
        let changes = PermissionSnapshot.diff(last, now)
        last = now
        if !changes.isEmpty { onChange?(changes, now) }
        onTick?(now)
    }
}
