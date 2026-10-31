import SwiftUI

/// 04 录音中：与第九版 RecordingMotionDemo / RecordingChromePanel 一致。
struct DemoScreen: View {
    @Environment(\.designIsPad) private var isPad
    /// recording | result | idle
    var phase: String = "recording"
    var animateIn: Bool = false

    @State private var show = false
    @State private var recording = true
    @State private var pressed = false
    @State private var recStart = Date()

    private let prompt = "你好小明，跟你说一下我换新手机号码了，是 13812345678。谢谢，Jack。哦对，小明是黄晓明的晓明。"

    var body: some View {
        ZStack {
            SaycribeColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "mic")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SaycribeColor.orange)
                            .padding(.top, 2)
                        Text("点击麦克风，阅读下面的消息，然后再次点击以插入所说的文本。")
                            .font(SaycribeType.subhead)
                            .foregroundStyle(SaycribeColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, isPad ? 28 : 16)

                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(SaycribeColor.textTertiary.opacity(0.45))
                            .frame(width: 2)
                        Text(prompt)
                            .font(SaycribeType.body)
                            .foregroundStyle(SaycribeColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(SaycribeColor.orange)
                            Text("备忘录")
                                .font(SaycribeType.subheadMedium)
                                .foregroundStyle(SaycribeColor.textPrimary)
                            Spacer()
                        }
                        ZStack(alignment: .leading) {
                            if phase == "result" {
                                Text("晓明，你好：\n\n跟你说一下，我换新手机号码了：138 1234 5678。\n\n谢谢，\nJack")
                                    .font(SaycribeType.subhead)
                                    .foregroundStyle(SaycribeColor.textPrimary)
                            } else {
                                Rectangle()
                                    .fill(SaycribeColor.orange)
                                    .frame(width: 2, height: 18)
                                    .padding(.leading, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(SaycribeColor.bgElevated)
                        )
                    }
                    .padding(14)
                    .background(DarkCardBackground(radius: SaycribeRadius.lg))
                    .appearScaleOpacity(show, from: 0.96)

                    HStack(spacing: 12) {
                        secondaryPill("返回")
                        Spacer(minLength: 0)
                        if phase == "result" {
                            PrimaryButton(title: "继续", enabled: true, style: .bright)
                                .frame(width: 120)
                        } else {
                            secondaryPill("继续")
                        }
                    }
                }
                .padding(.horizontal, isPad ? 72 : 22)
                .frame(maxWidth: isPad ? 720 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity)
                .appearScaleOpacity(show)

                Spacer(minLength: 8)

                RecordingChromePanel(
                    recording: recording && phase != "result",
                    recStart: recStart,
                    pressed: pressed,
                    source: SimulatedAudioLevel(loudOnly: true)
                ) {
                    withAnimation(Motion.island) { recording.toggle() }
                }
                .appearScaleOpacity(show, from: 0.94)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            recording = (phase != "result" && phase != "idle")
            recStart = Date()
            if animateIn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(Motion.window) { show = true }
                }
            } else {
                show = true
            }
        }
    }

    private func secondaryPill(_ title: String) -> some View {
        Text(title)
            .font(SaycribeType.subheadMedium)
            .foregroundStyle(SaycribeColor.textPrimary)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(SaycribeColor.card))
            .overlay(Capsule().stroke(SaycribeColor.border, lineWidth: 1))
    }
}

#Preview("演示-录音") { DemoScreen(phase: "recording").environment(\.designIsPad, false) }
#Preview("演示-结果") { DemoScreen(phase: "result").environment(\.designIsPad, false) }
