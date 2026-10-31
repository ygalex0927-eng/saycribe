import SwiftUI

/// 05 键盘布局：第五版结构 + 第九版音量缩放；无第六版草稿/中英胶囊/点按说话·ZH。
struct KeyboardLayoutScreen: View {
    @Environment(\.designIsPad) private var isPad
    var mode: String = "语音"
    var recording: Bool = false
    var animateIn: Bool = false

    @State private var show = false

    var body: some View {
        ZStack {
            SaycribeColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("备忘录")
                        .font(SaycribeType.footnote)
                        .foregroundStyle(SaycribeColor.textTertiary)
                        .padding(.top, isPad ? 28 : 16)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(recording ? "正在听…" : "下午三点开会，")
                            .font(SaycribeType.body)
                            .foregroundStyle(SaycribeColor.textPrimary)
                        if !recording {
                            Rectangle()
                                .fill(SaycribeColor.orange)
                                .frame(width: 2, height: 20)
                                .padding(.leading, 1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, isPad ? 40 : 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .appearScaleOpacity(show)

                SaycribeKeyboardPanel(mode: mode, recording: recording, showGuide: false)
                    .frame(height: isPad ? 360 : 320)
                    .appearScaleOpacity(show, from: 0.96)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if animateIn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(Motion.keyboardFollow) { show = true }
                }
            } else {
                show = true
            }
        }
    }
}

struct SaycribeKeyboardPanel: View {
    var mode: String
    var recording: Bool = false
    var showGuide: Bool = false
    var interactive: Bool = false

    @State private var currentMode: String = "语音"
    @State private var isRecording: Bool = false
    @State private var recStart = Date()
    @Namespace private var modeNS
    private let modes = ["语音", "EN", "拼"]

    var body: some View {
        ZStack(alignment: .top) {
            SaycribeColor.keyboardBg.ignoresSafeArea(edges: .bottom)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        AppLogoMark(size: 22)
                        Text("Saycribe")
                            .font(SaycribeType.subheadMedium)
                            .foregroundStyle(SaycribeColor.textPrimary)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(modes, id: \.self) { m in
                            Button {
                                guard interactive else { return }
                                withAnimation(Motion.morph) { currentMode = m }
                            } label: {
                                Group {
                                    if m == "语音" {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 13, weight: .bold))
                                    } else {
                                        Text(m)
                                            .font(SaycribeType.caption)
                                    }
                                }
                                .foregroundStyle(m == currentMode ? SaycribeColor.textPrimary : SaycribeColor.textTertiary)
                                .frame(minWidth: 36)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background {
                                    if m == currentMode {
                                        Capsule()
                                            .fill(SaycribeColor.keyCap)
                                            .matchedGeometryEffect(id: "modePill", in: modeNS)
                                            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(
                        Capsule()
                            .fill(SaycribeColor.bg.opacity(0.55))
                            .overlay(Capsule().stroke(SaycribeColor.border, lineWidth: 1))
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                HStack(alignment: .center, spacing: 14) {
                    VStack(spacing: 12) {
                        roundKey("arrow.uturn.backward")
                        roundKey("pencil.line", accent: true)
                    }

                    VStack(spacing: 10) {
                        Text(isRecording ? "再次点击以完成" : "点击说话")
                            .font(SaycribeType.overline)
                            .foregroundStyle(SaycribeColor.textSecondary)
                            .animation(Motion.morph, value: isRecording)

                        Button {
                            guard interactive else { return }
                            if !isRecording { recStart = Date() }
                            withAnimation(Motion.island) { isRecording.toggle() }
                        } label: {
                            VoiceCapsule(recording: isRecording, start: recStart,
                                         source: SimulatedAudioLevel(loudOnly: true))
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.96))
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 12) {
                        roundKey("delete.left")
                        roundKey("at")
                    }
                }
                .padding(.horizontal, 20)

                HStack {
                    Image(systemName: "globe")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(SaycribeColor.textSecondary)
                        .frame(width: 44, height: 36)
                    Spacer()
                    Text("换行")
                        .font(SaycribeType.subheadMedium)
                        .foregroundStyle(SaycribeColor.textPrimary)
                        .frame(width: 108, height: 40)
                        .background(Capsule().fill(SaycribeColor.keyCap))
                        .overlay(Capsule().stroke(SaycribeColor.border, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .padding(.top, 4)
            }

            if showGuide {
                KeyboardGuideOverlay(page: 0)
                    .padding(.top, 48)
                    .padding(.horizontal, 16)
            }
        }
        .onAppear {
            currentMode = mode
            isRecording = recording
            recStart = Date()
        }
        .onChange(of: mode) { _, v in
            withAnimation(Motion.morph) { currentMode = v }
        }
        .onChange(of: recording) { _, v in
            if v { recStart = Date() }
            withAnimation(Motion.island) { isRecording = v }
        }
    }

    private func roundKey(_ icon: String, accent: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(accent ? SaycribeColor.orange : SaycribeColor.textPrimary)
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(accent ? SaycribeColor.orangeSoft : SaycribeColor.keyCap)
            )
            .overlay(
                Circle()
                    .stroke(accent ? SaycribeColor.orange.opacity(0.35) : SaycribeColor.border, lineWidth: 1)
            )
    }
}

#Preview("键盘布局") { KeyboardLayoutScreen().environment(\.designIsPad, false) }
