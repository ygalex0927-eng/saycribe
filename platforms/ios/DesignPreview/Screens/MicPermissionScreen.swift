import SwiftUI

/// 2. 麦克风权限预热页：手机模型动画示意点 Allow
struct MicPermissionScreen: View {
    @Environment(\.designIsPad) private var isPad

    var body: some View {
        VStack(spacing: 0) {
            FakeStatusBar()
            Spacer(minLength: 12)
            VStack(spacing: 18) {
                Text("需要用一下麦克风")
                    .font(SaycribeFont.title(isPad ? 32 : 26))
                    .foregroundStyle(SaycribeColor.textPrimary)
                Text("下一步系统会弹出权限框。请点「允许」，Saycribe 才能把你的话说成文字。")
                    .font(SaycribeFont.body(15))
                    .foregroundStyle(SaycribeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, isPad ? 80 : 28)
            }

            Spacer(minLength: 16)

            // 手机模型 + 系统权限弹窗示意
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(SaycribeColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .stroke(SaycribeColor.border, lineWidth: 3)
                    )
                    .frame(width: isPad ? 280 : 220, height: isPad ? 520 : 420)
                    .overlay(alignment: .top) {
                        Capsule().fill(SaycribeColor.textPrimary.opacity(0.18))
                            .frame(width: 70, height: 8)
                            .padding(.top, 14)
                    }
                    .overlay {
                        VStack(spacing: 16) {
                            AppLogoMark(size: 56)
                            Text("Saycribe")
                                .font(SaycribeFont.medium(18))
                                .foregroundStyle(SaycribeColor.textPrimary)
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(SaycribeColor.orange)
                                .padding(.top, 8)
                            Spacer()
                        }
                        .padding(.top, 48)
                    }

                // 权限弹窗
                VStack(spacing: 0) {
                    Text("“Saycribe”想访问麦克风")
                        .font(SaycribeFont.medium(15))
                        .foregroundStyle(SaycribeColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                    Text("Saycribe 需要麦克风来把你的语音转成文字。")
                        .font(SaycribeFont.body(12))
                        .foregroundStyle(SaycribeColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    Divider()
                    HStack(spacing: 0) {
                        Text("不允许")
                            .font(SaycribeFont.body(16))
                            .foregroundStyle(SaycribeColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        Rectangle().fill(SaycribeColor.border).frame(width: 1, height: 44)
                        Text("允许")
                            .font(SaycribeFont.medium(16))
                            .foregroundStyle(SaycribeColor.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8).stroke(SaycribeColor.orange, lineWidth: 2).padding(4)
                            )
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                .frame(width: isPad ? 300 : 260)
                .offset(y: isPad ? -40 : -24)
            }

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                PrimaryButton(title: "继续")
                Text("演示：请在弹窗里点右侧「允许」")
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
}

#Preview("麦克风-iPhone") { MicPermissionScreen().environment(\.designIsPad, false) }
