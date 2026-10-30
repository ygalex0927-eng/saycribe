import AppKit

/// `Saycribe --unit-tests` — pure-logic checks that need no microphone, models, or network. Exit 1 on any failure.
enum UnitTests {
    private static var failures = 0
    private static var passed = 0

    static func check(_ ok: Bool, _ name: String, file: String = #file, line: Int = #line) {
        if ok { passed += 1 } else { failures += 1; print("FAIL \(name) (\((file as NSString).lastPathComponent):\(line))") }
    }

    static func run() -> Never {
        permissions()
        clipboard()
        hotkeys()
        print("\(passed) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - #13 custom hotkey

    static func hotkeys() {
        let cmd = CGEventFlags.maskCommand.rawValue, opt = CGEventFlags.maskAlternate.rawValue
        let ctrl = CGEventFlags.maskControl.rawValue, shift = CGEventFlags.maskShift.rawValue
        let rcmd = HotkeySpec(keyCode: 54, modifierOnly: true)
        check(rcmd.isDown(CGEventFlags(rawValue: cmd | 0x10)), "hk: right cmd down")
        check(!rcmd.isDown(CGEventFlags(rawValue: cmd | 0x08)), "hk: left cmd is not right cmd")
        check(HotkeySpec.fn.isDown(.maskSecondaryFn), "hk: fn")
        let combo = HotkeySpec(keyCode: 49, modifiers: ctrl | opt, modifierOnly: false)
        check(combo.keycap == "⌃⌥Space", "hk: keycap \(combo.keycap)")
        check(combo.matches(keyCode: 49, flags: CGEventFlags(rawValue: ctrl | opt | 0x100)), "hk: combo matches (ignores device bits)")
        check(combo.matches(keyCode: 49, flags: CGEventFlags(rawValue: ctrl | opt | CGEventFlags.maskSecondaryFn.rawValue)), "hk: ignores fn flag")
        check(!combo.matches(keyCode: 49, flags: CGEventFlags(rawValue: ctrl | opt | shift)), "hk: extra modifier rejects")
        check(!combo.matches(keyCode: 49, flags: CGEventFlags(rawValue: ctrl)), "hk: missing modifier rejects")
        check(!rcmd.matches(keyCode: 54, flags: CGEventFlags(rawValue: cmd)), "hk: modifier-only never matches as combo")
        check(HotkeySpec.problem(combo) == nil, "hk: ⌃⌥Space ok")
        check(HotkeySpec.problem(HotkeySpec(keyCode: 96, modifierOnly: false)) == nil, "hk: bare F5 ok")
        check(HotkeySpec.problem(HotkeySpec(keyCode: 0, modifierOnly: false)) != nil, "hk: bare A rejected")
        check(HotkeySpec.problem(HotkeySpec(keyCode: 0, modifiers: shift, modifierOnly: false)) != nil, "hk: ⇧A rejected")
        check(HotkeySpec.problem(HotkeySpec(keyCode: 8, modifiers: cmd, modifierOnly: false)) != nil, "hk: ⌘C rejected")
        check(HotkeySpec.problem(HotkeySpec(keyCode: 53, modifiers: ctrl, modifierOnly: false)) != nil, "hk: Esc rejected")
        check(HotkeySpec.problem(HotkeySpec(keyCode: 49, modifiers: ctrl, modifierOnly: false)) != nil, "hk: ⌃Space (input source) rejected")
        check(HotkeySpec.legacy("rightOption") == HotkeySpec(keyCode: 61, modifierOnly: true), "hk: legacy migration")
        let data = try! JSONEncoder().encode(combo)
        check((try? JSONDecoder().decode(HotkeySpec.self, from: data)) == combo, "hk: codable")
        check(TranslateCombo.cmdOpt.matches(CGEventFlags(rawValue: cmd | opt | 0x10)), "tr: ⌘⌥")
        check(!TranslateCombo.cmdOpt.matches(CGEventFlags(rawValue: cmd | opt | shift)), "tr: ⌘⌥⇧ no")
        check(TranslateCombo.ctrlOpt.matches(CGEventFlags(rawValue: ctrl | opt)), "tr: ⌃⌥")
        check(!TranslateCombo.off.matches(CGEventFlags(rawValue: cmd | opt)), "tr: off")
    }

    // MARK: - #15 selection fallback, clipboard restore

    static func clipboard() {
        check(Inserter.clampDelay(0.1) == 0.3 && Inserter.clampDelay(9) == 3 && Inserter.clampDelay(1.2) == 1.2, "clip: clamp")
        check(AppContext.needsCopyFallback(.unsupported, enabled: true), "sel: fallback when AX hides it")
        check(!AppContext.needsCopyFallback(.unsupported, enabled: false), "sel: off switch")
        check(!AppContext.needsCopyFallback(.empty, enabled: true), "sel: no ⌘C when nothing selected")
        check(!AppContext.needsCopyFallback(.text("x"), enabled: true), "sel: no ⌘C when AX has text")
        let pb = NSPasteboard(name: NSPasteboard.Name("com.zjh.suikou.unittest"))
        pb.clearContents()
        pb.setString("原来的", forType: .string)
        pb.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.zjh.test"))
        let snap = Inserter.snapshot(pb)
        pb.clearContents(); pb.setString("临时", forType: .string)
        Inserter.restore(snap, to: pb)
        check(pb.string(forType: .string) == "原来的", "clip: restore string")
        check(pb.data(forType: NSPasteboard.PasteboardType("com.zjh.test")) == Data([1, 2, 3]), "clip: restore custom type")
        Inserter.restore([], to: pb)
        check(pb.string(forType: .string) == nil, "clip: restore empty")
        pb.releaseGlobally()
    }

    // MARK: - #3 permissions

    static func permissions() {
        let all = PermissionSnapshot(microphone: true, accessibility: true, inputMonitoring: true)
        var noInput = all; noInput.inputMonitoring = false
        var noAX = all; noAX.accessibility = false
        check(PermissionSnapshot.diff(all, all).isEmpty, "perm: no change")
        check(PermissionSnapshot.diff(all, noInput) == [.lost(.inputMonitoring)], "perm: lost input")
        check(PermissionSnapshot.diff(noInput, all) == [.regained(.inputMonitoring)], "perm: regained input")
        check(PermissionSnapshot.diff(noAX, noInput) == [.regained(.accessibility), .lost(.inputMonitoring)], "perm: swap")
        check(noInput.missing == [.inputMonitoring], "perm: missing")
        check(all.missing.isEmpty, "perm: none missing")
        // Watcher fires onChange only for real changes.
        let w = PermissionWatcher()
        var calls = 0
        w.onChange = { _, _ in calls += 1 }
        w.poll(); w.poll()
        check(calls == 0, "perm: watcher stable")
        // Monitor without a tap is unhealthy, stop() is safe twice.
        let hk = HotkeyMonitor()
        check(!hk.isHealthy, "hotkey: unhealthy before start")
        hk.stop(); hk.stop()
        check(hk.state == .idle, "hotkey: stop idempotent")
    }
}
