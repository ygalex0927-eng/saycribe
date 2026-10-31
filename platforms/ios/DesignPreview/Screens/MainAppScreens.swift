import SwiftUI

/// 7. 主 App 各 Tab
struct HomeStatsScreen: View {
    @Environment(\.designIsPad) private var isPad
    var body: some View {
        VStack(spacing: 0) {
            FakeStatusBar()
            VStack(alignment: .leading, spacing: 18) {
                header(title: "今日", subtitle: "说话越清楚，整理越省事")
                HStack(spacing: 12) {
                    statCard(title: "字数", value: "2,480", unit: "字", icon: "textformat")
                    statCard(title: "语速", value: "168", unit: "字/分", icon: "speedometer")
                }
                HStack(spacing: 12) {
                    statCard(title: "时长", value: "14", unit: "分钟", icon: "clock")
                    statCard(title: "会话", value: "9", unit: "次", icon: "bubble.left.and.bubble.right")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("本周趋势")
                        .font(SaycribeFont.medium(15))
                        .foregroundStyle(SaycribeColor.textPrimary)
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array([0.4, 0.55, 0.35, 0.7, 0.9, 0.6, 0.75].enumerated()), id: \.offset) { i, h in
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(i == 4 ? SaycribeColor.orange : SaycribeColor.orangeSoft)
                                    .frame(height: 90 * h)
                                Text(["一","二","三","四","五","六","日"][i])
                                    .font(SaycribeFont.medium(11))
                                    .foregroundStyle(SaycribeColor.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                    .background(SaycribeColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous).stroke(SaycribeColor.border, lineWidth: 1))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, isPad ? 48 : 20)
            .frame(maxWidth: isPad ? 900 : .infinity)
            .frame(maxWidth: .infinity)
            TabBarMock(selected: 0)
        }
        .designCanvas(isPad: isPad)
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SaycribeFont.title(isPad ? 30 : 26)).foregroundStyle(SaycribeColor.textPrimary)
                Text(subtitle).font(SaycribeFont.body(14)).foregroundStyle(SaycribeColor.textSecondary)
            }
            Spacer()
            AppLogoMark(size: 36)
        }
        .padding(.top, 8)
    }

    private func statCard(title: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).foregroundStyle(SaycribeColor.orange)
                Text(title).font(SaycribeFont.medium(13)).foregroundStyle(SaycribeColor.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(SaycribeFont.display(28)).foregroundStyle(SaycribeColor.textPrimary)
                Text(unit).font(SaycribeFont.body(13)).foregroundStyle(SaycribeColor.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaycribeColor.card)
        .clipShape(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous).stroke(SaycribeColor.border, lineWidth: 1))
    }
}

struct HistoryScreen: View {
    @Environment(\.designIsPad) private var isPad
    private let rows: [(String, String, Bool)] = [
        ("今天下午三点开会，记得带上上周的纪要。", "刚刚", true),
        ("把 Q3 方案里的风险那一段再压缩一下。", "昨天", false),
        ("周末去博物馆，门票我先买。", "周一", false),
    ]
    var body: some View {
        VStack(spacing: 0) {
            FakeStatusBar()
            VStack(alignment: .leading, spacing: 14) {
                Text("历史")
                    .font(SaycribeFont.title(isPad ? 30 : 26))
                    .foregroundStyle(SaycribeColor.textPrimary)
                    .padding(.top, 8)
                Text("左滑可复制").font(SaycribeFont.body(13)).foregroundStyle(SaycribeColor.textTertiary)

                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        historyRow(text: row.0, time: row.1, revealCopy: row.2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, isPad ? 48 : 20)
            .frame(maxWidth: isPad ? 900 : .infinity)
            .frame(maxWidth: .infinity)
            TabBarMock(selected: 1)
        }
        .designCanvas(isPad: isPad)
    }

    private func historyRow(text: String, time: String, revealCopy: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(SaycribeFont.body(15))
                    .foregroundStyle(SaycribeColor.textPrimary)
                    .lineLimit(2)
                Text(time).font(SaycribeFont.body(12)).foregroundStyle(SaycribeColor.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SaycribeColor.card)

            if revealCopy {
                Text("复制")
                    .font(SaycribeFont.medium(14))
                    .foregroundStyle(.white)
                    .frame(width: 72)
                    .frame(maxHeight: .infinity)
                    .background(SaycribeColor.orange)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SaycribeRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SaycribeRadius.md, style: .continuous).stroke(SaycribeColor.border, lineWidth: 1))
    }
}

struct LexiconScreen: View {
    @Environment(\.designIsPad) private var isPad
    private let words = ["Saycribe", "纪要", "Q3 方案", "牙膏哥", "中转接口"]
    var body: some View {
        VStack(spacing: 0) {
            FakeStatusBar()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("词库")
                        .font(SaycribeFont.title(isPad ? 30 : 26))
                        .foregroundStyle(SaycribeColor.textPrimary)
                    Spacer()
                    Text("添加")
                        .font(SaycribeFont.medium(14))
                        .foregroundStyle(SaycribeColor.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(SaycribeColor.orangeSoft))
                }
                .padding(.top, 8)
                Text("专有名词会优先保留原样，减少误识别。")
                    .font(SaycribeFont.body(14))
                    .foregroundStyle(SaycribeColor.textSecondary)

                VStack(spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.offset) { idx, w in
                        HStack {
                            Text(w).font(SaycribeFont.body(16)).foregroundStyle(SaycribeColor.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SaycribeColor.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        if idx < words.count - 1 {
                            Divider().overlay(SaycribeColor.border).padding(.leading, 16)
                        }
                    }
                }
                .background(SaycribeColor.card)
                .clipShape(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous).stroke(SaycribeColor.border, lineWidth: 1))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, isPad ? 48 : 20)
            .frame(maxWidth: isPad ? 900 : .infinity)
            .frame(maxWidth: .infinity)
            TabBarMock(selected: 2)
        }
        .designCanvas(isPad: isPad)
    }
}

struct DesignSettingsScreen: View {
    @Environment(\.designIsPad) private var isPad
    var body: some View {
        VStack(spacing: 0) {
            FakeStatusBar()
            VStack(alignment: .leading, spacing: 14) {
                Text("设置")
                    .font(SaycribeFont.title(isPad ? 30 : 26))
                    .foregroundStyle(SaycribeColor.textPrimary)
                    .padding(.top, 8)

                group {
                    row("中转地址", "saycribe-api.motomotos.com")
                    Divider().overlay(SaycribeColor.border).padding(.leading, 16)
                    row("设备 token", "已保存")
                    Divider().overlay(SaycribeColor.border).padding(.leading, 16)
                    row("整理语气", "notes")
                }
                group {
                    row("识别模型", "SenseVoice int8 · 本机")
                    Divider().overlay(SaycribeColor.border).padding(.leading, 16)
                    row("隐私", "识别本机 · 整理不保留")
                }
                group {
                    row("使用引导", "")
                    Divider().overlay(SaycribeColor.border).padding(.leading, 16)
                    row("关于 Saycribe", "0.1.0")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, isPad ? 48 : 20)
            .frame(maxWidth: isPad ? 900 : .infinity)
            .frame(maxWidth: .infinity)
            TabBarMock(selected: 3)
        }
        .designCanvas(isPad: isPad)
    }

    private func group<Content: View>(@ViewBuilder _ c: () -> Content) -> some View {
        VStack(spacing: 0, content: c)
            .background(SaycribeColor.card)
            .clipShape(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous).stroke(SaycribeColor.border, lineWidth: 1))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(SaycribeFont.body(16)).foregroundStyle(SaycribeColor.textPrimary)
            Spacer()
            if !value.isEmpty {
                Text(value).font(SaycribeFont.body(14)).foregroundStyle(SaycribeColor.textTertiary).lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SaycribeColor.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview("首页") { HomeStatsScreen().environment(\.designIsPad, false) }
#Preview("历史") { HistoryScreen().environment(\.designIsPad, false) }
#Preview("词库") { LexiconScreen().environment(\.designIsPad, false) }
#Preview("设置") { DesignSettingsScreen().environment(\.designIsPad, false) }
