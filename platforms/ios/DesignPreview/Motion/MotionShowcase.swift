import SwiftUI

/// 三页动效：01 隐私 / 04 录音中 / 05 键盘。无假状态栏、无调试水印。
/// launch：
///   -designMode motion            → 自动串播（录屏）
///   -designMode page -designPage privacy|recording|keyboard → 定格单页（截图）
struct MotionShowcaseRoot: View {
    @State private var page = 0

    private var lockedPage: Int? {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-designPage"), i + 1 < args.count {
            switch args[i + 1].lowercased() {
            case "privacy", "0", "01": return 0
            case "recording", "4", "04", "1": return 1
            case "keyboard", "5", "05", "2": return 2
            default: break
            }
        }
        if let s = UserDefaults.standard.string(forKey: "designPage") {
            switch s.lowercased() {
            case "privacy", "0", "01": return 0
            case "recording", "4", "04", "1": return 1
            case "keyboard", "5", "05", "2": return 2
            default: break
            }
        }
        return nil
    }

    var body: some View {
        ZStack {
            SaycribeColor.bg.ignoresSafeArea()
            Group {
                switch page {
                case 0: PrivacyMotionDemo()
                case 1: RecordingMotionDemo()
                default: KeyboardMotionDemo()
                }
            }
            .id(page)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97)),
                removal: .opacity
            ))
        }
        .preferredColorScheme(.dark)
        .animation(Motion.window, value: page)
        .task {
            if let locked = lockedPage {
                page = locked
                return
            }
            await runShow()
        }
    }

    @MainActor
    private func runShow() async {
        // 隐私 → 录音 → 键盘，约 22–28s，便于 15–30s 录屏裁切
        page = 0
        try? await Task.sleep(nanoseconds: 7_500_000_000)
        withAnimation(Motion.window) { page = 1 }
        try? await Task.sleep(nanoseconds: 8_500_000_000)
        withAnimation(Motion.window) { page = 2 }
        try? await Task.sleep(nanoseconds: 9_000_000_000)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? "motion_done\n".write(
            to: docs.appendingPathComponent("_motion_done.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}

// MARK: - 01 隐私
struct PrivacyMotionDemo: View {
    @State private var showCards = false
    @State private var agreed = false
    @State private var pressFlash = false

    var body: some View {
        ZStack {
            SaycribeColor.bg.ignoresSafeArea()
            RadialGradient(
                colors: [SaycribeColor.orangeDeep.opacity(0.07), .clear],
                center: .topTrailing, startRadius: 20, endRadius: 420
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 36)
                VStack(alignment: .leading, spacing: 20) {
                    Text("隐私")
                        .font(SaycribeType.overline)
                        .foregroundStyle(SaycribeColor.orange)
                        .appearScaleOpacity(showCards)
                    Text("设计上是私密的")
                        .font(SaycribeType.title1)
                        .foregroundStyle(SaycribeColor.textPrimary)
                        .appearScaleOpacity(showCards, from: 0.96)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 20) {
                            VStack(spacing: 8) {
                                Text("在设备上")
                                    .font(SaycribeType.subheadMedium)
                                    .foregroundStyle(SaycribeColor.textPrimary)
                                Capsule().fill(SaycribeColor.orange).frame(width: 36, height: 3)
                            }
                            VStack(spacing: 8) {
                                Text("整理服务")
                                    .font(SaycribeType.subheadMedium)
                                    .foregroundStyle(SaycribeColor.textTertiary)
                                Capsule().fill(Color.clear).frame(width: 36, height: 3)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

                        FeatureRow(icon: "lock.fill", title: "识别在本机完成",
                                   subtitle: "语音转文字在你的设备上跑，原始音频不会上传。")
                            .padding(.horizontal, 20)
                        Divider().overlay(SaycribeColor.border).padding(.horizontal, 20)
                        FeatureRow(icon: "nosign", title: "整理经服务器且不保留",
                                   subtitle: "口语整理经中转服务处理，处理完即丢弃。")
                            .padding(.horizontal, 20)
                        Divider().overlay(SaycribeColor.border).padding(.horizontal, 20)
                        FeatureRow(icon: "iphone", title: "系统键盘随处可用",
                                   subtitle: "装好后可在任意输入框切换到 Saycribe。")
                            .padding(.horizontal, 20).padding(.bottom, 8)
                    }
                    .background(DarkCardBackground(radius: SaycribeRadius.xl))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                    .appearScaleOpacity(showCards, from: 0.94)

                    Button {
                        withAnimation(Motion.pop) { agreed.toggle() }
                    } label: {
                        CheckboxRow(checked: agreed, text: "我已了解：识别在本机；整理经服务器且不保留。同意继续。")
                    }
                    .buttonStyle(.plain)
                    .appearScaleOpacity(showCards)

                    PrimaryButton(title: "同意并继续", enabled: agreed, style: .bright)
                        .scaleEffect(pressFlash ? 0.96 : 1)
                        .animation(Motion.press, value: pressFlash)
                        .appearScaleOpacity(showCards)
                }
                .padding(.horizontal, 24)
                Spacer(minLength: 24)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(Motion.smooth) { showCards = true }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(Motion.pop) { agreed = true }
            try? await Task.sleep(nanoseconds: 900_000_000)
            pressFlash = true
            try? await Task.sleep(nanoseconds: 160_000_000)
            pressFlash = false
            try? await Task.sleep(nanoseconds: 700_000_000)
            pressFlash = true
            try? await Task.sleep(nanoseconds: 160_000_000)
            pressFlash = false
        }
    }
}

// MARK: - 04 录音中（第九版 = 第五版全橙按钮 + 音量大幅弹簧缩放）
struct RecordingMotionDemo: View {
    @State private var show = false
    @State private var recording = true
    @State private var pressFlash = false
    @State private var recStart = Date()

    private let prompt = "你好小明，跟你说一下我换新手机号码了，是 13812345678。谢谢，Jack。哦对，小明是黄晓明的晓明。"
    private var loudOnly: Bool { ProcessInfo.processInfo.arguments.contains("-loud") }

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
                    }
                    .padding(.top, 20)

                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(SaycribeColor.textTertiary.opacity(0.45))
                            .frame(width: 2)
                        Text(prompt)
                            .font(SaycribeType.body)
                            .foregroundStyle(SaycribeColor.textPrimary)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill").foregroundStyle(SaycribeColor.orange)
                            Text("备忘录").font(SaycribeType.subheadMedium)
                            Spacer()
                        }
                        Rectangle()
                            .fill(SaycribeColor.orange)
                            .frame(width: 2, height: 18)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(SaycribeColor.bgElevated))
                    }
                    .padding(14)
                    .background(DarkCardBackground(radius: SaycribeRadius.lg))
                }
                .padding(.horizontal, 22)
                .appearScaleOpacity(show)

                Spacer(minLength: 8)

                RecordingChromePanel(
                    recording: recording,
                    recStart: recStart,
                    pressed: pressFlash,
                    source: SimulatedAudioLevel(loudOnly: loudOnly)
                ) {
                    withAnimation(Motion.island) { recording.toggle() }
                }
                .appearScaleOpacity(show, from: 0.95)
            }
        }
        .task {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-loud") {
                recStart = Date()
                withAnimation(Motion.window) { show = true }
                return
            }
            if args.contains("-idle") {
                recording = false
                withAnimation(Motion.window) { show = true }
                return
            }
            if args.contains("-recFlow") {
                // 录屏：空闲 → 按下 0.96 → 录音（大声→小声→停顿→再大声）
                recording = false
                withAnimation(Motion.window) { show = true }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                pressFlash = true
                try? await Task.sleep(nanoseconds: 200_000_000)
                pressFlash = false
                recStart = Date()
                withAnimation(Motion.island) { recording = true }
                return
            }
            withAnimation(Motion.window) { show = true }
        }
    }
}
// MARK: - 05 键盘（第五版布局 + 第九版音量弹簧缩放；去掉第六版草稿/中英/点按说话·ZH）
struct KeyboardMotionDemo: View {
    @State private var mode = "语音"
    @State private var recording = false
    @State private var keyboardOffset: CGFloat = 48
    @State private var showHost = false
    @State private var pressFlash = false
    @State private var recStart = Date()
    @Namespace private var ns
    private let modes = ["语音", "EN", "拼"]

    var body: some View {
        ZStack {
            SaycribeColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("备忘录")
                        .font(SaycribeType.footnote)
                        .foregroundStyle(SaycribeColor.textTertiary)
                        .padding(.top, 20)
                    HStack(spacing: 0) {
                        Text(recording ? "正在听…" : "下午三点开会，")
                            .font(SaycribeType.body)
                            .foregroundStyle(SaycribeColor.textPrimary)
                        if !recording {
                            Rectangle().fill(SaycribeColor.orange).frame(width: 2, height: 20)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(showHost ? 1 : 0)

                VStack(spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            AppLogoMark(size: 22)
                            Text("Saycribe").font(SaycribeType.subheadMedium)
                                .foregroundStyle(SaycribeColor.textPrimary)
                        }
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(modes, id: \.self) { m in
                                Group {
                                    if m == "语音" {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 13, weight: .bold))
                                    } else {
                                        Text(m).font(SaycribeType.caption)
                                    }
                                }
                                .foregroundStyle(m == mode ? SaycribeColor.textPrimary : SaycribeColor.textTertiary)
                                .frame(minWidth: 36)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background {
                                    if m == mode {
                                        Capsule().fill(SaycribeColor.keyCap)
                                            .matchedGeometryEffect(id: "modePill", in: ns)
                                            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                                    }
                                }
                                .onTapGesture { withAnimation(Motion.morph) { mode = m } }
                            }
                        }
                        .padding(3)
                        .background(
                            Capsule().fill(SaycribeColor.bg.opacity(0.55))
                                .overlay(Capsule().stroke(SaycribeColor.border, lineWidth: 1))
                        )
                    }
                    .padding(.horizontal, 16).padding(.top, 14)

                    HStack(alignment: .center, spacing: 14) {
                        VStack(spacing: 12) {
                            roundKey("arrow.uturn.backward")
                            roundKey("pencil.line", accent: true)
                        }
                        VStack(spacing: 10) {
                            Text(recording ? "再次点击以完成" : "点击说话")
                                .font(SaycribeType.overline)
                                .foregroundStyle(SaycribeColor.textSecondary)
                            Button {
                                if !recording { recStart = Date() }
                                withAnimation(Motion.island) { recording.toggle() }
                            } label: {
                                VoiceCapsule(recording: recording, start: recStart, pressed: pressFlash)
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
                    .padding(.horizontal, 20).padding(.bottom, 22).padding(.top, 4)
                }
                .background(SaycribeColor.keyboardBg)
                .offset(y: keyboardOffset)
                .animation(Motion.keyboardFollow, value: keyboardOffset)
            }
        }
        .task {
            let locked = ProcessInfo.processInfo.arguments.contains("-designPage")
                || UserDefaults.standard.string(forKey: "designPage") != nil
            withAnimation(Motion.fade) { showHost = true }
            withAnimation(Motion.keyboardFollow) { keyboardOffset = 0 }
            recording = false
            mode = "语音"
            if locked { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            for m in ["EN", "拼", "语音"] {
                withAnimation(Motion.morph) { mode = m }
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
            // 按下 → 录音（音量缩放）→ 停
            pressFlash = true
            try? await Task.sleep(nanoseconds: 180_000_000)
            pressFlash = false
            recStart = Date()
            withAnimation(Motion.island) { recording = true }
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            withAnimation(Motion.island) { recording = false }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(Motion.morph) { mode = "EN" }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(Motion.morph) { mode = "语音" }
        }
    }

    private func roundKey(_ icon: String, accent: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(accent ? SaycribeColor.orange : SaycribeColor.textPrimary)
            .frame(width: 48, height: 48)
            .background(Circle().fill(accent ? SaycribeColor.orangeSoft : SaycribeColor.keyCap))
            .overlay(Circle().stroke(accent ? SaycribeColor.orange.opacity(0.35) : SaycribeColor.border, lineWidth: 1))
    }
}

