import AppKit
import SwiftUI

/// `Suikou --render-ui DIR` — renders every page (light + dark) and each HUD state to PNGs with sample data,
/// so the UI can be reviewed without clicking through the app.
enum UIRender {
    static func run(outDir: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("suikou-render-history.json")
        try? FileManager.default.removeItem(at: tmp)
        let history = History(url: tmp)
        for (i, s) in samples.enumerated().reversed() {
            history.add(HistoryEntry(date: Date().addingTimeInterval(-Double(i) * 2400 - (i > 3 ? 86400 : 0)),
                                     app: s.0, raw: s.1, text: s.2, ms: 900 + i * 130, audioSeconds: 4,
                                     mode: i == 4 ? "translate:en" : nil))
        }
        let stats = Stats()
        let controller = MainWindowController(history: history, stats: stats, onReloadModel: {})

        let savedOnboarding = Settings.shared.hasCompletedOnboarding
        Settings.shared.hasCompletedOnboarding = true
        for appearance in [("dark", NSAppearance.Name.darkAqua)] {
            for page in Page.allCases {
                controller.nav.page = page
                let window = controller.makeWindow()
                window.appearance = NSAppearance(named: appearance.1)
                window.setContentSize(NSSize(width: 860, height: page == .settings ? 1180 : 620))
                snapshot(window.contentView!, to: out.appendingPathComponent("\(page.rawValue)-\(appearance.0).png"))
                window.close()
            }
        }
        Settings.shared.hasCompletedOnboarding = false
        do {
            let window = controller.makeWindow()
            window.appearance = NSAppearance(named: .darkAqua)
            window.setContentSize(NSSize(width: 860, height: 620))
            snapshot(window.contentView!, to: out.appendingPathComponent("onboarding-dark.png"))
            window.close()
        }
        Settings.shared.hasCompletedOnboarding = savedOnboarding

        let hud = HUDController()
        let states: [(String, HUDModel.Phase, Bool)] = [
            ("listening", .listening, false), ("editing", .listening, true), ("locked", .locked, false),
            ("translate", .listening, false), ("thinking", .thinking, false), ("done", .done, false), ("error", .error("窗口已切换，结果已复制"), false),
        ]
        for (name, phase, editing) in states {
            hud.model.phase = phase
            hud.model.editing = editing
            hud.model.translateLabel = name == "translate" ? "EN" : nil
            hud.model.visible = true
            for _ in 0..<20 { hud.model.meter.push(rms: 0.06) }
            let host = NSHostingView(rootView:
                HUDView(model: hud.model)
                    .background(LinearGradient(colors: [Color(white: 0.93), Color(white: 0.82)], startPoint: .top, endPoint: .bottom)))
            host.frame = NSRect(origin: .zero, size: HUDController.size)
            let w = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.contentView = host
            snapshot(host, to: out.appendingPathComponent("hud-\(name).png"))
        }
        exit(0)
    }

    private static func snapshot(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static let samples: [(String, String, String)] = [
        ("微信", "嗯那个我们明天三点不对四点开会然后记得带电脑", "我们明天 4 点开会，记得带电脑"),
        ("Mail", "这次上线有几点要注意首先要备份数据库其次通知客服最后是灰度发布", "这次上线有几点要注意：\n1. 备份数据库\n2. 通知客服\n3. 灰度发布"),
        ("Cursor", "帮我把这个function改成async的然后加一个try catch", "帮我把这个 function 改成 async 的，然后加一个 try catch"),
        ("备忘录", "华真宣的新视频是用希德ance做的", "华臻轩的新视频是用 Seedance 做的"),
        ("Slack", "嗯我们周二上午十点碰一下吧", "Let's meet on Tuesday at 10 a.m."),
        ("飞书", "转化率提升了百分之二十三点五一共两千三百个用户", "转化率提升了 23.5%，一共 2300 个用户。"),
    ]
}
