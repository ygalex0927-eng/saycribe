import SwiftUI

@main
struct DesignExportApp: App {
    /// -designMode motion|page|export
    private var mode: String {
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-designMode"),
           i + 1 < ProcessInfo.processInfo.arguments.count {
            return ProcessInfo.processInfo.arguments[i + 1]
        }
        return UserDefaults.standard.string(forKey: "designMode") ?? "motion"
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if mode == "motion" || mode == "page" {
                    MotionShowcaseRoot()
                } else {
                    ExportHost()
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct ExportHost: View {
    @State private var status = "准备导出设计稿…"
    @State private var done = false

    var body: some View {
        ZStack {
            SaycribeColor.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                AppLogoMark(size: 56)
                Text("Saycribe 设计稿导出")
                    .font(SaycribeFont.title(22))
                    .foregroundStyle(SaycribeColor.textPrimary)
                Text(status)
                    .font(SaycribeFont.body(14))
                    .foregroundStyle(SaycribeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if done {
                    Text("可以关掉模拟器了")
                        .font(SaycribeFont.medium(14))
                        .foregroundStyle(SaycribeColor.success)
                }
            }
        }
        .task { await exportAll() }
    }

    @MainActor
    private func exportAll() async {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("设计稿", isDirectory: true)
        let phoneDir = root.appendingPathComponent("iPhone", isDirectory: true)
        let padDir = root.appendingPathComponent("iPad", isDirectory: true)
        try? fm.createDirectory(at: phoneDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: padDir, withIntermediateDirectories: true)

        let phone = CGSize(width: 393, height: 852)
        let pad = CGSize(width: 834, height: 1194)

        let jobs: [(String, AnyView, AnyView)] = [
            ("01-隐私说明",
             AnyView(PrivacyScreen().environment(\.designIsPad, false)),
             AnyView(PrivacyScreen().environment(\.designIsPad, true))),
            ("02-麦克风权限预热",
             AnyView(MicPermissionScreen().environment(\.designIsPad, false)),
             AnyView(MicPermissionScreen().environment(\.designIsPad, true))),
            ("03-添加键盘",
             AnyView(AddKeyboardScreen().environment(\.designIsPad, false)),
             AnyView(AddKeyboardScreen().environment(\.designIsPad, true))),
            ("04-互动演示-录音中",
             AnyView(DemoScreen(phase: "recording").environment(\.designIsPad, false)),
             AnyView(DemoScreen(phase: "recording").environment(\.designIsPad, true))),
            ("04b-互动演示-结果",
             AnyView(DemoScreen(phase: "result").environment(\.designIsPad, false)),
             AnyView(DemoScreen(phase: "result").environment(\.designIsPad, true))),
            ("05-键盘布局",
             AnyView(KeyboardLayoutScreen().environment(\.designIsPad, false)),
             AnyView(KeyboardLayoutScreen().environment(\.designIsPad, true))),
            ("06-键盘内引导卡",
             AnyView(KeyboardGuideScreen(page: 0).environment(\.designIsPad, false)),
             AnyView(KeyboardGuideScreen(page: 0).environment(\.designIsPad, true))),
            ("06b-键盘内引导卡-帮我写",
             AnyView(KeyboardGuideScreen(page: 1).environment(\.designIsPad, false)),
             AnyView(KeyboardGuideScreen(page: 1).environment(\.designIsPad, true))),
            ("07-首页统计",
             AnyView(HomeStatsScreen().environment(\.designIsPad, false)),
             AnyView(HomeStatsScreen().environment(\.designIsPad, true))),
            ("08-历史",
             AnyView(HistoryScreen().environment(\.designIsPad, false)),
             AnyView(HistoryScreen().environment(\.designIsPad, true))),
            ("09-词库",
             AnyView(LexiconScreen().environment(\.designIsPad, false)),
             AnyView(LexiconScreen().environment(\.designIsPad, true))),
            ("10-设置",
             AnyView(DesignSettingsScreen().environment(\.designIsPad, false)),
             AnyView(DesignSettingsScreen().environment(\.designIsPad, true))),
        ]

        var ok = 0
        for (name, phoneView, padView) in jobs {
            status = "导出 \(name)…"
            if render(phoneView, size: phone, to: phoneDir.appendingPathComponent("\(name).png")) { ok += 1 }
            if render(padView, size: pad, to: padDir.appendingPathComponent("\(name).png")) { ok += 1 }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let marker = root.appendingPathComponent("_export_done.txt")
        try? "exported=\(ok)\nroot=\(root.path)\n".write(to: marker, atomically: true, encoding: .utf8)
        status = "已导出 \(ok) 张到 Documents/设计稿/"
        done = true
        print("[DesignExport] done count=\(ok) path=\(root.path)")
    }

    @MainActor
    private func render<V: View>(_ view: V, size: CGSize, to url: URL) -> Bool {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let image = renderer.uiImage, let data = image.pngData() else {
            print("[DesignExport] FAIL \(url.lastPathComponent)")
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            print("[DesignExport] OK \(url.lastPathComponent) \(data.count)B")
            return true
        } catch {
            print("[DesignExport] WRITE \(error)")
            return false
        }
    }
}
