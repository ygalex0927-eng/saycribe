import SwiftUI

/// Saycribe 配色：来自牙膏哥指定的品牌规范（暗色）。只许黑 / 暖灰 / 暖白 / 陶土橙。
enum SaycribeColor {
    /// 主背景
    static let bg = Color(hex: 0x0C0C0B)
    /// 次级背景：bg 上叠白 4%（暖黑，无色偏）
    static let bgElevated = Color(hex: 0x141412)
    /// 卡片
    static let card = Color(hex: 0x1A1917)
    /// 卡片抬起一档
    static let cardRaised = Color(hex: 0x2A2826)
    /// 陶土橙：accent 暗 #E08A6C / 橙本体 #D97757
    static let orange = Color(hex: 0xE08A6C)
    static let orangeDeep = Color(hex: 0xD97757)
    /// 橙软底 = #D97757 @20%
    static let orangeSoft = Color(hex: 0xD97757, opacity: 0.20)
    /// 文字层级
    static let textPrimary = Color(hex: 0xF5F3EE)
    static let textSecondary = Color(hex: 0x9A968C)
    static let textTertiary = Color(hex: 0x5C584F)
    /// sep 白 10%；fill 白 8%
    static let border = Color.white.opacity(0.10)
    static let borderStrong = Color.white.opacity(0.16)
    static let fill = Color.white.opacity(0.08)
    /// 状态色也收进三色：成功用暖白，警示用橙
    static let success = Color(hex: 0xF5F3EE)
    static let danger = Color(hex: 0xD97757)
    /// 键盘区
    static let keyboardBg = Color(hex: 0x1A1917)
    static let keyCap = Color(hex: 0x22211F)
    /// 主 CTA / 空闲录音钮：暖白底 + 深字
    static let surfaceBright = Color(hex: 0xF5F3EE)
    static let onBright = Color(hex: 0x0C0C0B)

    static let warmBg = bg
}

/// 字体层级：来自牙膏哥指定的品牌规范（SF Pro / PingFang / SF Mono）
enum SaycribeType {
    static func f(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w) }
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size, weight: w, design: .monospaced) }
    static let largeTitle = f(34, .bold)
    static let title1 = f(28, .bold)
    static let title3 = f(20, .semibold)
    static let headline = f(17, .semibold)
    static let body = f(17)
    static let subhead = f(15)
    static let subheadMedium = f(15, .medium)
    static let footnote = f(13)
    static let caption = f(12)
    static let overline = mono(11, .medium)
}

enum SaycribeRadius {
    static let xl: CGFloat = 28
    static let lg: CGFloat = 22
    static let md: CGFloat = 16
    static let sm: CGFloat = 12
    static let pill: CGFloat = 999
}

enum SaycribeFont {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static func medium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

struct DesignCanvas: ViewModifier {
    var isPad: Bool
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SaycribeColor.bg.ignoresSafeArea())
            .environment(\.designIsPad, isPad)
            .preferredColorScheme(.dark)
    }
}

private struct DesignIsPadKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var designIsPad: Bool {
        get { self[DesignIsPadKey.self] }
        set { self[DesignIsPadKey.self] = newValue }
    }
}

extension View {
    func designCanvas(isPad: Bool) -> some View { modifier(DesignCanvas(isPad: isPad)) }
}
