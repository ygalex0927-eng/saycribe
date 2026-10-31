import SwiftUI

/// 动效弹簧参数：来自牙膏哥指定的品牌规范。spring(response:dampingFraction:)
enum Motion {
    /// 弹出、徽标，明显回弹
    static let pop = Animation.spring(response: 0.42, dampingFraction: 0.58)
    /// 页面和卡片展开
    static let smooth = Animation.spring(response: 0.50, dampingFraction: 0.86)
    /// 形变、切换
    static let morph = Animation.spring(response: 0.34, dampingFraction: 0.74)
    /// 弹窗、面板进场
    static let window = Animation.spring(response: 0.40, dampingFraction: 0.62)
    /// 聚焦、几乎不回弹
    static let focus = Animation.spring(response: 0.70, dampingFraction: 0.96)
    /// 灵动岛形变（过冲约 1.095）
    static let island = Animation.spring(response: 0.52, dampingFraction: 0.60)
    /// Live Activity：spring(duration: 0.6, bounce: 0.32)
    static let liveActivity = Animation.spring(duration: 0.6, bounce: 0.32)

    static let exit = Animation.timingCurve(0.5, 0, 0.75, 0, duration: 0.42)
    static let fade = Animation.timingCurve(0, 0, 0.58, 1, duration: 0.18)
    /// 按钮按下
    static let press = Animation.easeOut(duration: 0.15)
    /// 滚动顶栏收起
    static let scrollCollapse = Animation.easeOut(duration: 0.26)
    /// 键盘跟随
    static let keyboardFollow = Animation.easeOut(duration: 0.25)
}

/// 按钮按下缩放到约 0.96，easeOut 0.15s（来自牙膏哥指定的品牌规范）
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// 列表/卡片进出场：scale + opacity
struct AppearScaleOpacity: ViewModifier {
    var shown: Bool
    var scaleFrom: CGFloat = 0.92
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : scaleFrom)
    }
}

extension View {
    func appearScaleOpacity(_ shown: Bool, from: CGFloat = 0.92) -> some View {
        modifier(AppearScaleOpacity(shown: shown, scaleFrom: from))
            .animation(Motion.smooth, value: shown)
    }
}
