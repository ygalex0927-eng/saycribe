import SwiftUI

/// 6. 键盘内首次引导卡：滑动切键盘、点帮我写，分页小圆点
struct KeyboardGuideScreen: View {
    @Environment(\.designIsPad) private var isPad
    var page: Int = 0 // 0 滑动切键盘, 1 点帮我写

    var body: some View {
        VStack(spacing: 0) {
            FakeStatusBar()
            VStack(alignment: .leading, spacing: 10) {
                Text("微信")
                    .font(SaycribeFont.medium(13))
                    .foregroundStyle(SaycribeColor.textTertiary)
                chatBubble("你好，下午一起对一下稿？")
                Spacer(minLength: 0)
            }
            .padding(isPad ? 40 : 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            SaycribeKeyboardPanel(mode: "语音", showGuide: false)
                .frame(height: isPad ? 340 : 300)
                .overlay(alignment: .top) {
                    // 用 page 覆盖引导内容（面板内默认第 0 页，这里再画一层确保导出可控）
                    KeyboardGuideOverlay(page: page)
                        .padding(.top, 48)
                        .padding(.horizontal, 16)
                }
        }
        .designCanvas(isPad: isPad)
    }

    private func chatBubble(_ text: String) -> some View {
        Text(text)
            .font(SaycribeFont.body(16))
            .foregroundStyle(SaycribeColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SaycribeColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(SaycribeColor.border, lineWidth: 1))
    }
}

struct KeyboardGuideOverlay: View {
    var page: Int = 0
    private let pages: [(String, String, String)] = [
        ("hand.draw", "滑动切换键盘", "按住左下角地球键，滑到 Saycribe 即可。"),
        ("pencil.line", "点「帮我写」", "选中文字或直接点，让整理帮你润色这段话。"),
    ]

    var body: some View {
        let item = pages[min(max(page, 0), pages.count - 1)]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.0)
                    .foregroundStyle(SaycribeColor.orange)
                Text("快速上手")
                    .font(SaycribeFont.medium(13))
                    .foregroundStyle(SaycribeColor.textTertiary)
                Spacer()
                Text("跳过")
                    .font(SaycribeFont.medium(13))
                    .foregroundStyle(SaycribeColor.textTertiary)
            }
            Text(item.1)
                .font(SaycribeFont.title(18))
                .foregroundStyle(SaycribeColor.textPrimary)
            Text(item.2)
                .font(SaycribeFont.body(14))
                .foregroundStyle(SaycribeColor.textSecondary)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == page ? SaycribeColor.orange : SaycribeColor.border)
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                Text(page == 0 ? "下一页" : "知道了")
                    .font(SaycribeFont.medium(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(SaycribeColor.orange))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(SaycribeColor.card.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SaycribeRadius.lg, style: .continuous).stroke(SaycribeColor.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 16, y: 6)
    }
}

#Preview("引导卡") { KeyboardGuideScreen(page: 0).environment(\.designIsPad, false) }
