import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var coordinator: Coordinator!
    private var statusItem: NSStatusItem!
    private var mainWindow: MainWindowController!
    private var hotkeyRetry: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let resources = Bundle.main.resourceURL!
        coordinator = Coordinator(resources: resources)
        coordinator.loadRecognizer()
        mainWindow = MainWindowController(history: coordinator.history, stats: coordinator.stats,
                                          onReloadModel: { [weak self] in self?.coordinator.loadRecognizer() })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Saycribe")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        AudioRecorder.requestPermission { _ in }
        startHotkeys()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.writeStatus() }
        NSApp.mainMenu = Self.makeMainMenu()
        MainWindowController.applyDockPolicy(windowOpen: false)
        if !Permissions.allGranted {
            mainWindow.show(.settings)
        } else if !launchedAsLoginItem {
            mainWindow.show(.home)
        }
    }

    /// Clicking the app icon (Desktop, Dock, Launchpad) while it's already running opens the console.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    private var launchedAsLoginItem: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Needed once the app is a regular app with the console open: gives ⌘Q/⌘W and makes ⌘C/⌘V work in text fields.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Saycribe", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Saycribe", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Saycribe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }

    /// The event tap can only be created once Input Monitoring is granted; keep retrying until it is.
    private func startHotkeys() {
        if coordinator.hotkeys.start() { return }
        CGRequestListenEventAccess()
        hotkeyRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            if self?.coordinator.hotkeys.start() == true { t.invalidate() }
        }
    }

    /// Self-report for troubleshooting: ~/Library/Application Support/Suikou/status.json
    private func writeStatus() {
        let hk = coordinator.hotkeys
        let fmt = ISO8601DateFormatter()
        let status: [String: Any] = [
            "updated": fmt.string(from: Date()),
            "microphone": Permissions.microphone,
            "accessibility": Permissions.accessibility,
            "inputMonitoring": Permissions.inputMonitoring,
            "hotkeyTapActive": hk.isActive,
            "hotkey": Settings.shared.hotkey.rawValue,
            "hotkeyState": "\(hk.state)",
            "lastModifierKeyCode": hk.lastFlagsKeyCode,
            "lastModifierAt": hk.lastFlagsAt.map { fmt.string(from: $0) } ?? "never",
            "modelReady": coordinator.isModelReady,
            "apiKeySet": !Settings.shared.apiKey.isEmpty,
            "historyCount": coordinator.history.entries.count,
        ]
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Suikou")
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("status.json"), options: .atomic)
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status: String
        if !Permissions.allGranted { status = "权限未开齐，点「设置…」查看" }
        else if !coordinator.isModelReady { status = "语音模型加载中…" }
        else { status = "按住 \(Settings.shared.hotkey.keycap) 说话" }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let recent = NSMenuItem(title: "最近记录", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let entries = coordinator.history.entries.prefix(20)
        if entries.isEmpty { sub.addItem(withTitle: "还没有记录", action: nil, keyEquivalent: "") }
        for e in entries {
            let title = e.text.replacingOccurrences(of: "\n", with: " ")
            let item = NSMenuItem(title: title.count > 36 ? String(title.prefix(36)) + "…" : title,
                                  action: #selector(copyEntry(_:)), keyEquivalent: "")
            item.toolTip = "原始识别：\(e.raw)\n\(e.app) · \(e.ms)ms\n点击复制"
            item.representedObject = e.text
            item.target = self
            sub.addItem(item)
        }
        recent.submenu = sub
        menu.addItem(recent)

        let llm = NSMenuItem(title: "AI 整理", action: #selector(toggleLLM), keyEquivalent: "")
        llm.state = Settings.shared.llmEnabled ? .on : .off
        llm.target = self
        menu.addItem(llm)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "打开 Saycribe", action: #selector(openHome), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(withTitle: "退出 Saycribe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func toggleLLM() { Settings.shared.llmEnabled.toggle() }

    @objc private func openHome() { mainWindow.show(.home) }

    @objc private func openSettings() { mainWindow.show(.settings) }
}

if let i = CommandLine.arguments.firstIndex(of: "--render-ui") {
    UIRender.run(outDir: CommandLine.arguments[i + 1])
}
if let i = CommandLine.arguments.firstIndex(of: "--local-clean") {
    // `--local-clean STYLE TEXT...` prints LocalCleaner output per line, for checking the short-sentence path.
    let style = AppStyle(rawValue: CommandLine.arguments[i + 1]) ?? .notes
    for text in CommandLine.arguments[(i + 2)...] {
        print("\(text)  →  [\(LocalCleaner.clean(text, style: style))]  (\(Stats.count(text)) 字)")
    }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--selftest") {
    SelfTest.run(Array(CommandLine.arguments[(i + 1)...]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
