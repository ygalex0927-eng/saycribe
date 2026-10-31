import SwiftUI

/// 第九版录音页（主 App）：全橙 88pt 按钮 + 音量弹簧缩放 1+0.30×level。
struct RecordingView: View {
    @EnvironmentObject private var session: DictationSession
    @Environment(\.dismiss) private var dismiss

    private let bg = Color(red: 0x0C/255, green: 0x0C/255, blue: 0x0B/255)
    private let card = Color(red: 0x1A/255, green: 0x19/255, blue: 0x17/255)
    private let keyCap = Color(red: 0x22/255, green: 0x21/255, blue: 0x1F/255)
    private let orangeDeep = Color(red: 0xD9/255, green: 0x77/255, blue: 0x57/255)
    private let textPrimary = Color(red: 0xF5/255, green: 0xF3/255, blue: 0xEE/255)
    private let textSecondary = Color(red: 0x9A/255, green: 0x96/255, blue: 0x8C/255)
    private let border = Color.white.opacity(0.10)

    @State private var scaleLevel: Double = 0

    private var recording: Bool { session.state == .recording }
    private var busy: Bool {
        switch session.state {
        case .recognizing, .cleaning: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "mic")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(orangeDeep)
                            .padding(.top, 2)
                        Text("点击麦克风开始说话，再次点击以完成并插入文本。")
                            .font(.system(size: 15))
                            .foregroundStyle(textPrimary)
                    }
                    .padding(.top, 20)

                    statusBanner
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 8)

                VStack(spacing: 0) {
                    HStack {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(orangeDeep)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Image(systemName: "waveform")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(bg)
                                )
                            Text("Saycribe")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(textPrimary)
                        }
                        Spacer()
                        Button { session.cancelManual(); dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(keyCap))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)

                    if recording {
                        VStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Circle().fill(orangeDeep).frame(width: 6, height: 6)
                                Text(session.recordingStartedAt, style: .timer)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(textSecondary)
                            }
                            Text("再次点击以完成")
                                .font(.system(size: 13))
                                .foregroundStyle(textPrimary)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(
                                    Capsule().fill(Color(red: 0x2A/255, green: 0x28/255, blue: 0x26/255))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                                )
                        }
                    } else if busy {
                        Text(session.state == .recognizing ? "识别中…" : "整理中…")
                            .font(.system(size: 13))
                            .foregroundStyle(textSecondary)
                            .padding(.vertical, 8)
                    } else if session.state == .done {
                        Text("已完成")
                            .font(.system(size: 13))
                            .foregroundStyle(textSecondary)
                            .padding(.vertical, 8)
                    } else if session.state == .error {
                        Text(session.statusMessage.isEmpty ? "出错了" : session.statusMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(orangeDeep)
                            .padding(.vertical, 8)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    Button(action: tapMic) {
                        ZStack {
                            Circle()
                                .fill(orangeDeep)
                                .frame(width: 88, height: 88)
                                .shadow(color: orangeDeep.opacity(0.35), radius: 16, y: 6)
                            if recording {
                                Image(systemName: "waveform")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(textPrimary)
                                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: recording)
                            } else if busy {
                                ProgressView().tint(textPrimary)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(textPrimary)
                            }
                        }
                        .scaleEffect(1 + 0.30 * scaleLevel)
                        .animation(.spring(response: 0.42, dampingFraction: 0.58), value: scaleLevel)
                    }
                    .buttonStyle(AppPressScaleStyle())
                    .disabled(busy)
                    .padding(.vertical, 16)

                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundStyle(textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 22).padding(.bottom, 22)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(card)
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(border, lineWidth: 1))
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if session.state == .idle {
                // 从键盘 URL 跳进来时 DictationSession 已 start；手动打开则等用户点
            }
        }
        .onChange(of: session.audioLevel) { _, v in
            scaleLevel = recording ? v : 0
        }
        .onChange(of: session.state) { _, s in
            if s == .done || s == .error {
                // 稍留结果再关，方便自测看文案
            }
            if s != .recording { scaleLevel = 0 }
        }
    }

    private var statusBanner: some View {
        Group {
            if !session.lastText.isEmpty, session.state == .done {
                Text(session.lastText)
                    .font(.system(size: 17))
                    .foregroundStyle(textPrimary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(card))
            } else {
                EmptyView()
            }
        }
    }

    private func tapMic() {
        switch session.state {
        case .idle, .done, .error:
            session.startManual()
        case .recording:
            session.stopManual()
        default:
            break
        }
    }
}

private struct AppPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
