import SwiftUI

/// 01 隐私说明：对齐 Typeless 质感（大标题 + 深色卡片三卖点 + 勾选 + 白胶囊 CTA）
struct PrivacyScreen: View {
    @Environment(\.designIsPad) private var isPad
    var agreed: Bool = true
    var animateIn: Bool = false

    @State private var show = false
    @State private var checked = false

    var body: some View {
        ZStack {
            // 深色底 + 右上角微光，避免一片死黑
            SaycribeColor.bg.ignoresSafeArea()
            RadialGradient(
                colors: [SaycribeColor.orange.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [SaycribeColor.orangeDeep.opacity(0.04), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: isPad ? 48 : 28)

                VStack(alignment: .leading, spacing: isPad ? 28 : 22) {
                    Text("设计上是私密的")
                        .font(SaycribeFont.display(isPad ? 36 : 30))
                        .foregroundStyle(SaycribeColor.textPrimary)
                        .appearScaleOpacity(show, from: 0.96)

                    // 卡片：对齐 Typeless「在设备上」卖点卡
                    VStack(alignment: .leading, spacing: 0) {
                        // 分段标签
                        HStack(spacing: 20) {
                            VStack(spacing: 8) {
                                Text("在设备上")
                                    .font(SaycribeFont.medium(14))
                                    .foregroundStyle(SaycribeColor.textPrimary)
                                Capsule()
                                    .fill(SaycribeColor.orange)
                                    .frame(width: 36, height: 3)
                            }
                            VStack(spacing: 8) {
                                Text("整理服务")
                                    .font(SaycribeFont.medium(14))
                                    .foregroundStyle(SaycribeColor.textTertiary)
                                Capsule()
                                    .fill(Color.clear)
                                    .frame(width: 36, height: 3)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                        FeatureRow(
                            icon: "lock.fill",
                            title: "识别在本机完成",
                            subtitle: "语音转文字在你的设备上跑，原始音频不会上传到我们的服务器。"
                        )
                        .padding(.horizontal, 20)
                        Divider().overlay(SaycribeColor.border).padding(.horizontal, 20)
                        FeatureRow(
                            icon: "nosign",
                            title: "整理经服务器且不保留",
                            subtitle: "口语整理（去改口、标点）经我们的中转服务处理，处理完即丢弃，不保留原文。"
                        )
                        .padding(.horizontal, 20)
                        Divider().overlay(SaycribeColor.border).padding(.horizontal, 20)
                        FeatureRow(
                            icon: "iphone",
                            title: "系统键盘随处可用",
                            subtitle: "装好后可在微信、备忘录、邮件等任意输入框切换到 Saycribe。"
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                    .background(DarkCardBackground(radius: SaycribeRadius.xl))
                    .appearScaleOpacity(show, from: 0.94)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)

                    CheckboxRow(
                        checked: checked,
                        text: "我已了解：识别在本机；整理经我们的服务器且不保留。同意继续使用 Saycribe。"
                    )
                    .padding(.top, 8)
                    .appearScaleOpacity(show)
                }
                .padding(.horizontal, isPad ? 72 : 24)
                .frame(maxWidth: isPad ? 720 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 12)

                VStack(spacing: 10) {
                    PrimaryButton(title: "同意并继续", enabled: checked, style: .bright)
                    Text("可随时在设置里撤回同意")
                        .font(SaycribeFont.body(12))
                        .foregroundStyle(SaycribeColor.textTertiary)
                }
                .padding(.horizontal, isPad ? 72 : 24)
                .padding(.bottom, 36)
                .frame(maxWidth: isPad ? 720 : .infinity)
                .frame(maxWidth: .infinity)
                .appearScaleOpacity(show)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            checked = agreed
            if animateIn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(Motion.smooth) { show = true }
                }
            } else {
                show = true
            }
        }
    }
}

#Preview("隐私-iPhone") { PrivacyScreen().environment(\.designIsPad, false) }
