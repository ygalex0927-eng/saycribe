import SwiftUI

/// 3. 添加键盘页：动画教程 + 「设置里找不到键盘」排障
struct AddKeyboardScreen: View {
    @Environment(\.designIsPad) private var isPad

    var body: some View {
        VStack(spacing: 0) {
            FakeStatusBar()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("添加 Saycribe 键盘")
                        .font(SaycribeFont.title(isPad ? 32 : 26))
                        .foregroundStyle(SaycribeColor.textPrimary)
                        .padding(.top, 12)
                    Text("按下面三步，在系统设置里把键盘加进来，并打开「允许完全访问」。")
                        .font(SaycribeFont.body(15))
                        .foregroundStyle(SaycribeColor.textSecondary)

                    VStack(spacing: 12) {
                        stepCard(n: 1, title: "打开键盘列表",
                                 detail: "设置 → 通用 → 键盘 → 键盘 → 添加新键盘…")
                        stepCard(n: 2, title: "选择 Saycribe",
                                 detail: "在第三方键盘里找到 Saycribe，点一下添加。")
                        stepCard(n: 3, title: "允许完全访问",
                                 detail: "返回键盘列表，点 Saycribe，打开「允许完全访问」。没有它就无法联网整理，也无法和主 App 共享结果。")
                    }

                    // 简易「动画」示意：三帧横向
                    VStack(alignment: .leading, spacing: 10) {
                        Text("示意").font(SaycribeFont.medium(14)).foregroundStyle(SaycribeColor.textTertiary)
                        HStack(spacing: 10) {
                            animFrame(title: "设置", icon: "gear")
                            Image(systemName: "chevron.right").foregroundStyle(SaycribeColor.textTertiary)
                            animFrame(title: "添加键盘", icon: "keyboard")
                            Image(systemName: "chevron.right").foregroundStyle(SaycribeColor.textTertiary)
                            animFrame(title: "完全访问", icon: "lock.open", highlight: true)
                        }
                    }
                    .padding(.top, 4)

                    disclosure
                }
                .padding(.horizontal, isPad ? 72 : 24)
                .frame(maxWidth: isPad ? 760 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                PrimaryButton(title: "打开系统设置")
                Text("加好后回到这里继续")
                    .font(SaycribeFont.body(13))
                    .foregroundStyle(SaycribeColor.textTertiary)
            }
            .padding(.horizontal, isPad ? 72 : 24)
            .padding(.bottom, 28)
            .frame(maxWidth: isPad ? 560 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .designCanvas(isPad: isPad)
    }

    private func stepCard(n: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(SaycribeFont.medium(15))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(SaycribeColor.orange))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SaycribeFont.medium(16)).foregroundStyle(SaycribeColor.textPrimary)
                Text(detail).font(SaycribeFont.body(14)).foregroundStyle(SaycribeColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(SaycribeColor.card)
        .clipShape(RoundedRectangle(cornerRadius: SaycribeRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SaycribeRadius.md, style: .continuous).stroke(SaycribeColor.border, lineWidth: 1))
    }

    private func animFrame(title: String, icon: String, highlight: Bool = false) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(highlight ? SaycribeColor.orange : SaycribeColor.textPrimary)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(highlight ? SaycribeColor.orangeSoft : SaycribeColor.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(highlight ? SaycribeColor.orange : SaycribeColor.border, lineWidth: highlight ? 1.5 : 1)
                )
            Text(title).font(SaycribeFont.medium(11)).foregroundStyle(SaycribeColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("设置里找不到键盘？", systemImage: "questionmark.circle")
                .font(SaycribeFont.medium(15))
                .foregroundStyle(SaycribeColor.textPrimary)
            Text("有时「设置」会卡住旧状态。打开 App 切换器，把「设置」卡片上划关掉，再重新进入设置 → 通用 → 键盘。")
                .font(SaycribeFont.body(14))
                .foregroundStyle(SaycribeColor.textSecondary)
            Text("仍没有：确认本 App 已安装完成，并重启一次 iPhone / iPad。")
                .font(SaycribeFont.body(14))
                .foregroundStyle(SaycribeColor.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaycribeColor.orangeSoft.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: SaycribeRadius.md, style: .continuous))
    }
}

#Preview("添加键盘") { AddKeyboardScreen().environment(\.designIsPad, false) }
