import AppKit
import SwiftUI

// MARK: - Navigation

enum Page: String, CaseIterable, Identifiable {
    case home, history, dictionary, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .history: return "历史记录"
        case .dictionary: return "词典"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .history: return "clock"
        case .dictionary: return "character.book.closed"
        case .settings: return "gearshape"
        }
    }
}

final class AppNav: ObservableObject {
    @Published var page: Page = .home
}

// MARK: - Design tokens

enum UI {
    static let cardRadius: CGFloat = 14
    static let contentWidth: CGFloat = 600
    static let card = Brand.surface
    static let hairline = Color.white.opacity(0.07)
    static let mono = Font.system(size: 12, design: .monospaced)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous).strokeBorder(UI.hairline, lineWidth: 0.5))
    }
}

struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 21)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Brand.raised)
                    .shadow(color: .black.opacity(0.5), radius: 0, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 24, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.bottom, 8)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.top, 10)
    }
}

/// One line inside a settings card: title + optional subtitle on the left, a control on the right.
struct Row<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(UI.hairline).frame(height: 0.5).padding(.leading, 16) }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += lineH + spacing; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += lineH + spacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

// MARK: - Root

struct MainView: View {
    @ObservedObject var nav: AppNav
    let history: History
    let stats: Stats
    let onReloadModel: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(nav: nav)
                .frame(width: 200)
                .background(Brand.surface)
            Rectangle().fill(UI.hairline).frame(width: 1)
            ScrollView {
                Group {
                    switch nav.page {
                    case .home: HomePage(nav: nav, history: history, stats: stats)
                    case .history: HistoryPage(history: history)
                    case .dictionary: DictionaryPage()
                    case .settings: SettingsPage(onReloadModel: onReloadModel)
                    }
                }
                .frame(maxWidth: UI.contentWidth, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 44)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.ink)
        }
        .ignoresSafeArea()
        .frame(minWidth: 820, minHeight: 580)
    }
}

struct Sidebar: View {
    @ObservedObject var nav: AppNav

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                Text("Saycribe").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.top, 50)
            .padding(.bottom, 18)

            ForEach(Page.allCases) { page in
                SidebarItem(page: page, selected: nav.page == page) { nav.page = page }
            }
            Spacer()
            Text("v0.1 · local asr")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 10)
    }
}

struct SidebarItem: View {
    let page: Page
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .frame(width: 18)
                Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selected ? Brand.orange : (hover ? .primary : .secondary))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Brand.orange.opacity(0.13) : Color.white.opacity(hover ? 0.04 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Home

struct HomePage: View {
    @ObservedObject var nav: AppNav
    @ObservedObject var history: History
    @ObservedObject var stats: Stats
    @ObservedObject var settings = Settings.shared
    @State private var permissionsOK = Permissions.allGranted
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(greeting).font(.system(size: 26, weight: .semibold))
                    BlinkCursor()
                }
                HStack(spacing: 6) {
                    Text("按住").foregroundStyle(.secondary)
                    Keycap(label: settings.hotkey.keycap)
                    Text("说话，松开即写入。").foregroundStyle(.secondary)
                }
                .font(.system(size: 13.5))
                HStack(spacing: 6) {
                    Text("按住").foregroundStyle(.secondary)
                    HStack(spacing: 3) { Keycap(label: "⌘"); Keycap(label: "⌥") }
                    Text("说话，直接写出\(settings.currentTranslateTarget.name)译文。").foregroundStyle(.secondary)
                }
                .font(.system(size: 13.5))
            }

            if !permissionsOK {
                Card(padding: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Brand.accent).font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("还差几项权限").font(.system(size: 13, weight: .semibold))
                            Text("开启后才能听到快捷键、写入文字。").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("去设置") { nav.page = .settings }.controlSize(.regular)
                    }
                }
            }

            HStack(spacing: 12) {
                StatTile(value: "\(stats.words)", unit: "字", label: "累计口述")
                StatTile(value: "\(stats.minutesSaved)", unit: "分钟", label: "节省时间")
                StatTile(value: stats.wpm > 0 ? "\(stats.wpm)" : "—", unit: stats.wpm > 0 ? "字/分" : "", label: "说话速度")
            }

            HStack {
                SectionLabel(text: "最近")
                Spacer()
                if !history.entries.isEmpty {
                    Button("查看全部") { nav.page = .history }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                }
            }
            .padding(.bottom, -12)

            if history.entries.isEmpty {
                Card(padding: 28) {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform").font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary)
                        Text("还没有记录").font(.system(size: 13, weight: .medium))
                        Text("在任意输入框里按住快捷键，说一句话试试。").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Card {
                    ForEach(Array(history.entries.prefix(5).enumerated()), id: \.element.id) { i, e in
                        if i > 0 { RowDivider() }
                        HistoryRow(entry: e, compact: true, onDelete: nil)
                    }
                }
            }
        }
        .onReceive(timer) { _ in permissionsOK = Permissions.allGranted }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }
}

/// Terminal-style block cursor after the greeting.
struct BlinkCursor: View {
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Brand.orange)
            .frame(width: 11, height: 24)
            .opacity(on ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever()) { on = false } }
    }
}

struct StatTile: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        Card(padding: 16) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 28, weight: .semibold, design: .monospaced))
                Text(unit).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - History

struct HistoryPage: View {
    @ObservedObject var history: History
    @State private var query = ""
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "历史记录", subtitle: "最近 \(History.limit) 条，只保存在本机。") {
                if !history.entries.isEmpty {
                    Button("清空") { confirmClear = true }
                        .confirmationDialog("清空全部历史记录？", isPresented: $confirmClear) {
                            Button("清空", role: .destructive) { history.clear() }
                        }
                }
            }
            SearchField(text: $query)

            let groups = grouped
            if groups.isEmpty {
                Text(query.isEmpty ? "还没有记录" : "没有找到相关记录")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 40)
            }
            ForEach(groups, id: \.0) { title, items in
                SectionLabel(text: title).padding(.bottom, -8)
                Card {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { RowDivider() }
                        HistoryRow(entry: e, compact: false) { history.remove(e.id) }
                    }
                }
            }
        }
    }

    private var grouped: [(String, [HistoryEntry])] {
        let items = query.isEmpty ? history.entries : history.entries.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.raw.localizedCaseInsensitiveContains(query)
        }
        let cal = Calendar.current
        var out: [(String, [HistoryEntry])] = []
        for e in items {
            let title: String
            if cal.isDateInToday(e.date) { title = "今天" }
            else if cal.isDateInYesterday(e.date) { title = "昨天" }
            else { title = e.date.formatted(.dateTime.month().day().weekday()) }
            if out.last?.0 == title { out[out.count - 1].1.append(e) } else { out.append((title, [e])) }
        }
        return out
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("搜索", text: $text).textFieldStyle(.plain).font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(UI.hairline, lineWidth: 0.5))
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    let compact: Bool
    let onDelete: (() -> Void)?
    @State private var hover = false
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text)
                    .font(.system(size: 13))
                    .lineLimit(compact || !expanded ? 2 : nil)
                    .textSelection(.enabled)
                if expanded {
                    Text("原始识别：\(entry.raw)")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !compact {
                    Text(meta).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 60)
        }
        .overlay(alignment: compact ? .trailing : .topTrailing) {
            HStack(spacing: 2) {
                IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "复制") {
                    Inserter.copy(entry.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                if let onDelete { IconButton(symbol: "trash", help: "删除", action: onDelete) }
            }
            .opacity(hover || copied ? 1 : 0)
            .offset(y: compact ? 0 : -4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if !compact { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } }
    }

    private var meta: String {
        var parts: [String] = []
        if !entry.app.isEmpty { parts.append(entry.app) }
        parts.append(String(format: "%.1f 秒", Double(entry.ms) / 1000))
        if let mode = entry.mode, mode.hasPrefix("translate:") {
            let id = String(mode.dropFirst("translate:".count))
            parts.append("已翻译 · " + (Settings.translateTargets.first { $0.id == id }?.name ?? id))
        } else if entry.mode == "local" {
            parts.append("本地直出")
        } else if entry.raw != entry.text {
            parts.append("已整理")
        }
        return parts.joined(separator: " · ")
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5))
                .foregroundStyle(hover ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.07 : 0)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}

// MARK: - Dictionary

struct DictionaryPage: View {
    @ObservedObject var settings = Settings.shared
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "词典", subtitle: "人名、品牌、专业术语的正确写法。识别出错时，Saycribe 会按这里纠正。")
            HStack(spacing: 8) {
                TextField("添加一个词，例如「华臻轩」", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(UI.card))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(UI.hairline, lineWidth: 0.5))
                    .onSubmit(add)
                Button("添加", action: add)
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .controlSize(.large)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if settings.dictionary.isEmpty {
                Card(padding: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "character.book.closed").font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary)
                        Text("词典是空的").font(.system(size: 13, weight: .medium))
                        Text("常被识别错的词加进来，之后就会写对。").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Card(padding: 16) {
                    FlowLayout(spacing: 8) {
                        ForEach(settings.dictionary, id: \.self) { word in
                            Chip(text: word) { remove(word) }
                        }
                    }
                }
                Text("共 \(settings.dictionary.count) 个词").font(.system(size: 11.5)).foregroundStyle(.tertiary).padding(.leading, 4)
            }
        }
    }

    private func add() {
        let word = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !settings.dictionary.contains(word) else { draft = ""; return }
        settings.dictionaryText = (settings.dictionary + [word]).joined(separator: "\n")
        draft = ""
    }

    private func remove(_ word: String) {
        settings.dictionaryText = settings.dictionary.filter { $0 != word }.joined(separator: "\n")
    }
}

struct Chip: View {
    let text: String
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Text(text).font(.system(size: 12.5))
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0.35)
        }
        .padding(.leading, 11).padding(.trailing, 9)
        .frame(height: 28)
        .background(Capsule().fill(Brand.raised))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .onHover { hover = $0 }
    }
}

// MARK: - Settings

struct SettingsPage: View {
    @ObservedObject var settings = Settings.shared
    let onReloadModel: () -> Void
    @State private var tick = 0
    @State private var devices = AudioDevices.inputs()
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "设置")

            SectionLabel(text: "快捷键")
            Card {
                Row(title: "说话键", subtitle: "外接键盘的 fn 往往不会传给系统，选右侧 ⌘ 或 ⌥ 更稳。") {
                    Picker("", selection: $settings.hotkey) {
                        ForEach(Hotkey.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                RowDivider()
                HStack(spacing: 22) {
                    Gesture(keys: [settings.hotkey.keycap], text: "按住说话")
                    Gesture(keys: [settings.hotkey.keycap, settings.hotkey.keycap], text: "双击锁定")
                    Gesture(keys: ["esc"], text: "取消")
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }

            SectionLabel(text: "翻译")
            Card {
                Row(title: "翻译键", subtitle: "按住说任意语言，松开后直接写入译文。正在说话时补按 ⌥ 也会切到翻译。") {
                    HStack(spacing: 3) { Keycap(label: "⌘"); Keycap(label: "⌥") }
                }
                RowDivider()
                Row(title: "译成") {
                    Picker("", selection: $settings.translateTarget) {
                        ForEach(Settings.translateTargets) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                }
            }

            SectionLabel(text: "声音")
            Card {
                Row(title: "麦克风") {
                    Picker("", selection: $settings.micUID) {
                        Text("跟随系统").tag("")
                        ForEach(devices) { Text($0.name).tag($0.uid) }
                    }
                    .labelsHidden().fixedSize()
                }
                RowDivider()
                Row(title: "识别语言", subtitle: "说话中英混杂时选「自动」即可。") {
                    Picker("", selection: $settings.asrLanguage) {
                        ForEach(Settings.languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden().fixedSize()
                    .onChange(of: settings.asrLanguage) { _, _ in onReloadModel() }
                }
            }

            SectionLabel(text: "AI 整理")
            Card {
                Row(title: "整理口语", subtitle: "去掉口头禅和重复，听懂改口，补标点、排列表。关闭后只在本机做简单整理。") {
                    Toggle("", isOn: $settings.llmEnabled).toggleStyle(.switch).labelsHidden().tint(Brand.accent)
                }
                RowDivider()
                Row(title: "短句不调用 AI", subtitle: "不超过 \(settings.shortSentenceLimit) 个字的话在本机去掉口头禅、补好标点后直接写入，更快；长句仍交给 DeepSeek。翻译和改写不受影响。") {
                    HStack(spacing: 10) {
                        if settings.skipShortSentences {
                            Picker("", selection: $settings.shortSentenceLimit) {
                                ForEach(Settings.shortSentenceLimits, id: \.self) { Text("≤ \($0) 字").tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                        Toggle("", isOn: $settings.skipShortSentences).toggleStyle(.switch).labelsHidden().tint(Brand.accent)
                    }
                }
                RowDivider()
                Row(title: "整理模型") {
                    Picker("", selection: $settings.cleanModel) {
                        ForEach(Settings.models, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                RowDivider()
                Row(title: "改写模型", subtitle: "选中文字后说话，用来执行修改指令。") {
                    Picker("", selection: $settings.editModel) {
                        ForEach(Settings.models, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                RowDivider()
                Row(title: "DeepSeek API Key") {
                    SecureField("sk-…", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }

            SectionLabel(text: "通用")
            Card {
                Row(title: "提示音", subtitle: "开始和结束录音时轻响一声。") {
                    Toggle("", isOn: $settings.playSounds).toggleStyle(.switch).labelsHidden().tint(Brand.accent)
                }
                RowDivider()
                Row(title: "写入后保留在剪贴板", subtitle: "关闭时，写入完成会恢复你原来复制的内容。") {
                    Toggle("", isOn: $settings.keepInClipboard).toggleStyle(.switch).labelsHidden().tint(Brand.accent)
                }
                RowDivider()
                Row(title: "在程序坞显示图标", subtitle: "关闭时只在菜单栏显示；打开控制台时总会显示。") {
                    Toggle("", isOn: $settings.showInDock).toggleStyle(.switch).labelsHidden().tint(Brand.accent)
                        .onChange(of: settings.showInDock) { _, _ in MainWindowController.applyDockPolicy(windowOpen: true) }
                }
                RowDivider()
                Row(title: "登录时启动") {
                    Toggle("", isOn: $settings.launchAtLogin).toggleStyle(.switch).labelsHidden().tint(Brand.accent)
                }
            }

            SectionLabel(text: "权限")
            Card {
                PermissionRow(name: "麦克风", hint: "录音", ok: Permissions.microphone) {
                    AudioRecorder.requestPermission { _ in tick += 1 }
                    Permissions.open("Privacy_Microphone")
                }
                RowDivider()
                PermissionRow(name: "辅助功能", hint: "把文字写进输入框、读取选中的文字", ok: Permissions.accessibility) {
                    AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                    Permissions.open("Privacy_Accessibility")
                }
                RowDivider()
                PermissionRow(name: "输入监控", hint: "听到快捷键", ok: Permissions.inputMonitoring) {
                    CGRequestListenEventAccess()
                    Permissions.open("Privacy_ListenEvent")
                }
            }
            .id(tick)

            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 11))
                Text("录音只在本机识别，不会上传。发给 DeepSeek 的只有识别出的文字，以及改写时选中的文字。")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
            .padding(.leading, 4)
        }
        .onReceive(timer) { _ in
            tick += 1
            devices = AudioDevices.inputs()
        }
    }
}

struct Gesture: View {
    let keys: [String]
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) { ForEach(Array(keys.enumerated()), id: \.offset) { Keycap(label: $0.element) } }
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct PermissionRow: View {
    let name: String
    let hint: String
    let ok: Bool
    let action: () -> Void

    var body: some View {
        Row(title: name, subtitle: hint) {
            if ok {
                Label("已开启", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("去开启", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
            }
        }
    }
}

// MARK: - Window

final class MainWindowController: NSObject, NSWindowDelegate {
    let nav = AppNav()
    private var window: NSWindow?
    private let history: History
    private let stats: Stats
    private let onReloadModel: () -> Void

    init(history: History, stats: Stats, onReloadModel: @escaping () -> Void) {
        self.history = history
        self.stats = stats
        self.onReloadModel = onReloadModel
    }

    /// While the console is open the app shows in the Dock and ⌘-Tab, like a normal app.
    func show(_ page: Page? = nil) {
        if let page { nav.page = page }
        let isNew = window == nil
        if isNew {
            window = makeWindow()
            window?.delegate = self
        }
        NSApp.setActivationPolicy(.regular)
        if isNew { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Self.applyDockPolicy(windowOpen: false)
    }

    static func applyDockPolicy(windowOpen: Bool) {
        NSApp.setActivationPolicy(windowOpen || Settings.shared.showInDock ? .regular : .accessory)
    }

    func makeWindow() -> NSWindow {
        let root = MainView(nav: nav, history: history, stats: stats, onReloadModel: onReloadModel)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Saycribe"
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(Brand.ink)
        w.contentView = NSHostingView(rootView: root.preferredColorScheme(.dark))
        return w
    }
}
