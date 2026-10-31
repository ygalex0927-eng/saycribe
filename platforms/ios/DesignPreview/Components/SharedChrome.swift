import SwiftUI

/// 已废弃：真机/模拟器截图用系统状态栏（simctl status_bar override），不再画假状态栏。
struct FakeStatusBar: View {
    var time: String = "9:41"
    var body: some View { EmptyView() }
}

struct PrimaryButton: View {
    var title: String
    var enabled: Bool = true
    /// Typeless 风格：白底黑字胶囊；accent 模式为橙底白字
    var style: Style = .bright
    enum Style { case bright, accent }

    var body: some View {
        Button(action: {}) {
            Text(title)
                .font(SaycribeType.headline)
                .foregroundStyle(style == .bright ? SaycribeColor.onBright : SaycribeColor.onBright)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule()
                        .fill(enabled
                              ? (style == .bright ? SaycribeColor.surfaceBright : SaycribeColor.orange)
                              : (style == .bright ? SaycribeColor.surfaceBright.opacity(0.35) : SaycribeColor.orange.opacity(0.35)))
                }
                .shadow(color: .black.opacity(enabled ? 0.25 : 0), radius: 12, y: 4)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}

struct FeatureRow: View {
    var icon: String
    var title: String
    var subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SaycribeColor.orange)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SaycribeType.headline)
                    .foregroundStyle(SaycribeColor.textPrimary)
                Text(subtitle)
                    .font(SaycribeType.footnote)
                    .foregroundStyle(SaycribeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

struct CheckboxRow: View {
    var checked: Bool
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(checked ? SaycribeColor.orange : SaycribeColor.borderStrong, lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(checked ? SaycribeColor.orange : Color.clear)
                    )
                    .frame(width: 20, height: 20)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SaycribeColor.onBright)
                }
            }
            .padding(.top, 2)
            Text(text)
                .font(SaycribeType.footnote)
                .foregroundStyle(SaycribeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// 实时跳动声波：多根圆角竖条，正弦 + 随机扰动，spring 驱动。
struct LiveWaveform: View {
    var barCount: Int = 5
    var color: Color = SaycribeColor.onBright
    var barWidth: CGFloat = 3.5
    var spacing: CGFloat = 3.5
    var minHeight: CGFloat = 6
    var maxHeight: CGFloat = 26
    var active: Bool = true

    @State private var phase: Double = 0
    @State private var heights: [CGFloat] = []

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: active ? height(at: i) : minHeight)
            }
        }
        .frame(height: maxHeight)
        .onAppear {
            heights = Array(repeating: (minHeight + maxHeight) / 2, count: barCount)
            tick()
        }
        .onChange(of: active) { _, on in
            if on { tick() }
        }
    }

    private func height(at i: Int) -> CGFloat {
        guard heights.count == barCount else { return minHeight }
        return heights[i]
    }

    private func tick() {
        guard active else { return }
        phase += 0.55
        withAnimation(Motion.pop) {
            heights = (0..<barCount).map { i in
                let wave = abs(sin(phase + Double(i) * 0.9 + cos(phase * 0.35 + Double(i) * 0.4)))
                let jitter = Double.random(in: 0.85...1.08)
                return minHeight + CGFloat(wave * jitter) * (maxHeight - minHeight)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            tick()
        }
    }
}

/// 静态声波（导出静帧用）
struct WaveformBars: View {
    var active: Bool = true
    var color: Color = SaycribeColor.orange
    private let heights: [CGFloat] = [8, 16, 26, 14, 30, 18, 10, 28, 16, 22]
    var body: some View {
        HStack(alignment: .center, spacing: 3.5) {
            ForEach(0..<heights.count, id: \.self) { i in
                Capsule()
                    .fill(active ? color : SaycribeColor.borderStrong)
                    .frame(width: 3.5, height: active ? heights[i] : 8)
            }
        }
        .frame(height: 36)
    }
}

struct AppLogoMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(SaycribeColor.orange)
                .frame(width: size, height: size)
                .shadow(color: SaycribeColor.orange.opacity(0.35), radius: size * 0.2, y: 2)
            Image(systemName: "waveform")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(SaycribeColor.onBright)
        }
    }
}

struct TabBarMock: View {
    var selected: Int
    private let items: [(String, String)] = [
        ("chart.bar.fill", "首页"),
        ("clock", "历史"),
        ("text.book.closed", "词库"),
        ("gearshape", "设置"),
    ]
    var body: some View {
        HStack {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                VStack(spacing: 4) {
                    Image(systemName: item.0)
                        .font(.system(size: 20, weight: .semibold))
                    Text(item.1).font(SaycribeType.overline)
                }
                .foregroundStyle(idx == selected ? SaycribeColor.orange : SaycribeColor.textTertiary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 22)
        .background(SaycribeColor.card.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(SaycribeColor.border).frame(height: 1)
        }
    }
}

/// 深色卡片底板：细描边 + 轻微材质感
struct DarkCardBackground: View {
    var radius: CGFloat = SaycribeRadius.xl
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(SaycribeColor.card)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(SaycribeColor.border, lineWidth: 1)
            )
    }
}

/// 第六版「中英」胶囊已否；第九版统一用系统 globe。保留空实现以免旧引用崩。
@available(*, deprecated, message: "第九版用系统 globe，勿再使用中英胶囊")
struct LangSwitchChip: View {
    var body: some View { EmptyView() }
}
