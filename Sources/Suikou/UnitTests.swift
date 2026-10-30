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
        history()
        appStyles()
        segments()
        print("\(passed) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - #4 long recordings

    static func segments() {
        check(Segmenter.join(["今天开会", "  明天出差 "]) == "今天开会明天出差", "seg: cjk join")
        check(Segmenter.join(["hello", "world"]) == "hello world", "seg: latin join")
        check(Segmenter.join(["", "a", ""]) == "a", "seg: skip empty")
        let parts = (1...10).map { _ in String(repeating: "字", count: 90) }
        let g = Segmenter.group(parts, limit: 400)
        check(g.count == 3 && g.allSatisfy { $0.count <= 400 }, "seg: group by limit")
        check(Segmenter.group([String(repeating: "x", count: 900)], limit: 400).count == 1, "seg: oversize piece stays whole")
        check(Segmenter.cutPoints([(0, 100), (200, 50), (300, 10)], total: 400) == [150, 275], "seg: cut mid-pause")
        check(Segmenter.cutPoints([(0, 100)], total: 400).isEmpty, "seg: one span no cut")
        check(Segmenter.cutPoints([(0, 120), (100, 50)], total: 400) == [100], "seg: overlapping spans")
        check(AudioRecorder.maxSamples >= 16000 * 3600, "seg: recording cap ≥ 1h")
        let sem = DispatchSemaphore(value: 0)
        var joined = ""
        Task {
            joined = (try? await Segmenter.cleanAll(["一", "二", "三"]) { s in
                try await Task.sleep(nanoseconds: UInt64.random(in: 1...20) * 1_000_000); return "[\(s)]" }) ?? "ERR"
            sem.signal()
        }
        sem.wait()
        check(joined == "[一二三]", "seg: cleanAll keeps order (\(joined))")
    }

    // MARK: - #10 app styles

    static func appStyles() {
        check(AppStyle.forBundle("com.microsoft.VSCode") == .code, "style: vscode code")
        check(AppStyle.forBundle("com.tencent.xinWeChat") == .chat, "style: wechat chat")
        check(AppStyle.forBundle(nil) == .notes, "style: nil notes")
        let o = ["com.tencent.xinWeChat": "email", "com.foo.bad": "nonsense"]
        check(AppStyle.resolve("com.tencent.xinwechat", overrides: o) == .email, "style: override case-insensitive")
        check(AppStyle.resolve("com.foo.bad", overrides: o) == .notes, "style: bad override falls back")
        check(AppStyle.resolve("com.microsoft.VSCode", overrides: o) == .code, "style: no override")
        check(AppStyle.resolve(nil, overrides: o) == .notes, "style: nil with overrides")
    }

    // MARK: - #7 history

    static func history() {
        let now = Date()
        let e = { (daysAgo: Double, text: String) in
            HistoryEntry(date: now.addingTimeInterval(-daysAgo * 86400), app: "微信", raw: "嗯\(text)", text: text, ms: 300)
        }
        let list = [e(0.1, "今天"), e(3, "三天前"), e(10, "十天前"), e(40, "四十天前")]
        check(History.pruned(list, days: 0, now: now).count == 4, "hist: keep forever")
        check(History.pruned(list, days: 7, now: now).map(\.text) == ["今天", "三天前"], "hist: 7 days")
        check(History.pruned(list, days: 30, now: now).count == 3, "hist: 30 days")
        check(History.pruned(list, days: 1, now: now).count == 1, "hist: 1 day")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("suikou-unittest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let h = History(url: tmp)
        h.retentionDays = { 7 }
        for x in list.reversed() { h.add(x) }
        check(h.entries.map(\.text) == ["今天", "三天前"], "hist: add prunes")
        h.retentionDays = { 1 }
        h.prune(now: now)
        check(History(url: tmp).entries.map(\.text) == ["今天"], "hist: prune persisted")

        let tricky = HistoryEntry(date: now, app: "Mail", raw: "他说\"好\"，然后", text: "他说\"好\"，\n然后", ms: 1)
        let csv = History.export([tricky], as: .csv)
        check(csv.hasPrefix("\u{FEFF}时间,应用"), "export: csv header+BOM")
        check(csv.contains("\"他说\"\"好\"\"，\n然后\""), "export: csv quoting")
        check(csv.components(separatedBy: "\r\n").count == 3, "export: csv rows")
        let md = History.export([tricky, e(0, "第二条")], as: .markdown)
        check(md.contains("共 2 条") && md.contains("## ") && md.contains("> 原始识别：他说\"好\"，然后"), "export: markdown")
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
