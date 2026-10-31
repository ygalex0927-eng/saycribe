import SwiftUI

/// 音量 0…1。真实 App 里来自录音 RMS；DesignPreview 用模拟曲线。
protocol AudioLevelSource {
    func level(at t: TimeInterval) -> Double
}

/// 模拟曲线：大声 → 小声 → 停顿（≈0）→ 再大声，带自然抖动。
struct SimulatedAudioLevel: AudioLevelSource {
    var loudOnly = false
    static let softAt: TimeInterval = 3.5
    static let pauseAt: TimeInterval = 6.5
    static let loudAgainAt: TimeInterval = 9.0

    func level(at t: TimeInterval) -> Double {
        guard t > 0 else { return 0 }
        let jitter = 0.5 + 0.5 * sin(t * 9.1) * sin(t * 3.7 + 1.3)
        let base: Double
        if loudOnly || t < Self.softAt || t >= Self.loudAgainAt {
            base = 0.72 + 0.26 * jitter
        } else if t < Self.pauseAt {
            base = 0.18 + 0.14 * jitter
        } else {
            base = 0.02 * jitter
        }
        let attack = min(1, t / 0.25)
        return max(0, min(1, base * attack))
    }
}

/// 第五版全橙主按钮 + 第九版唯一增量：按钮整体随音量弹簧缩放 1 + 0.30 × level。
struct VoiceOrb: View {
    var recording: Bool
    var start: Date
    var pressed: Bool = false
    var source: AudioLevelSource = SimulatedAudioLevel()
    var diameter: CGFloat = 88

    static let scaleGain: CGFloat = 0.30

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(SaycribeColor.orangeDeep)
                .frame(width: diameter, height: diameter)
                .shadow(color: SaycribeColor.orangeDeep.opacity(0.35), radius: 16, y: 6)
            if recording {
                LiveWaveform(barCount: 5, color: SaycribeColor.textPrimary, barWidth: 4, spacing: 4,
                             minHeight: 8, maxHeight: 32, active: true)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(SaycribeColor.textPrimary)
            }
        }
        .scaleEffect(1 + Self.scaleGain * CGFloat(level))
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(Motion.press, value: pressed)
        .task(id: recording) {
            while !Task.isCancelled {
                let target = (recording && !reduceMotion)
                    ? min(1, max(0, source.level(at: Date().timeIntervalSince(start)))) : 0
                withAnimation(Motion.pop) { level = target }
                do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
            }
        }
    }
}

/// 键盘页第五版胶囊主按钮 + 第九版音量弹簧缩放（同 VoiceOrb 规则）。
struct VoiceCapsule: View {
    var recording: Bool
    var start: Date
    var pressed: Bool = false
    var source: AudioLevelSource = SimulatedAudioLevel()
    var idleWidth: CGFloat = 156
    var recordingWidth: CGFloat = 168
    var height: CGFloat = 58

    static let scaleGain: CGFloat = 0.30

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: Double = 0

    var body: some View {
        ZStack {
            Capsule()
                .fill(SaycribeColor.orangeDeep)
                .frame(width: recording ? recordingWidth : idleWidth, height: height)
                .shadow(color: SaycribeColor.orangeDeep.opacity(0.35), radius: 14, y: 5)
            if recording {
                LiveWaveform(barCount: 7, color: SaycribeColor.textPrimary,
                             barWidth: 3.5, spacing: 3.5,
                             minHeight: 8, maxHeight: 28, active: true)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SaycribeColor.textPrimary)
            }
        }
        .frame(height: height + 6)
        .scaleEffect(1 + Self.scaleGain * CGFloat(level))
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(Motion.press, value: pressed)
        .animation(Motion.morph, value: recording)
        .task(id: recording) {
            while !Task.isCancelled {
                let target = (recording && !reduceMotion)
                    ? min(1, max(0, source.level(at: Date().timeIntervalSince(start)))) : 0
                withAnimation(Motion.pop) { level = target }
                do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
            }
        }
    }
}

/// 第九版贴底录音面板：Logo+Saycribe / × / 计时+气泡 / VoiceOrb / 左下 globe。
struct RecordingChromePanel: View {
    var recording: Bool
    var recStart: Date
    var pressed: Bool = false
    var source: AudioLevelSource = SimulatedAudioLevel()
    var onToggle: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    AppLogoMark(size: 22)
                    Text("Saycribe").font(SaycribeType.subheadMedium)
                        .foregroundStyle(SaycribeColor.textPrimary)
                }
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SaycribeColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(SaycribeColor.keyCap))
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)

            if recording {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(SaycribeColor.orangeDeep).frame(width: 6, height: 6)
                        Text(recStart, style: .timer)
                            .font(SaycribeType.overline)
                            .monospacedDigit()
                            .foregroundStyle(SaycribeColor.textSecondary)
                    }
                    HStack(spacing: 6) {
                        Text("再次点击")
                        LiveWaveform(barCount: 5, color: SaycribeColor.textPrimary, barWidth: 2.5, spacing: 2.5,
                                     minHeight: 4, maxHeight: 12, active: true)
                            .frame(width: 28, height: 14)
                        Text("以完成")
                    }
                    .font(SaycribeType.footnote)
                    .foregroundStyle(SaycribeColor.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(SaycribeColor.cardRaised)
                        .overlay(Capsule().stroke(SaycribeColor.borderStrong, lineWidth: 1)))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Button {
                onToggle?()
            } label: {
                VoiceOrb(recording: recording, start: recStart, pressed: pressed, source: source)
            }
            .buttonStyle(PressScaleStyle(scale: 0.96))
            .padding(.vertical, 16)

            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(SaycribeColor.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 22).padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(SaycribeColor.keyboardBg)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(SaycribeColor.border, lineWidth: 1))
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(Motion.morph, value: recording)
    }
}
