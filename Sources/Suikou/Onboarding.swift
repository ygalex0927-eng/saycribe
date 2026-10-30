import AppKit
import SwiftUI

/// First-launch walkthrough: welcome → permissions → hotkey tip → done.
struct OnboardingView: View {
    @ObservedObject var settings = Settings.shared
    @State private var step = 0
    @State private var tick = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let steps = ["欢迎", "权限", "快捷键", "完成"]

    var body: some View {
        ZStack {
            Brand.ink.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(steps.indices, id: \.self) { i in
                        Capsule().fill(i <= step ? Brand.accent : Color.white.opacity(0.15))
                            .frame(width: i == step ? 28 : 10, height: 4)
                    }
                }
                .padding(.top, 28).padding(.bottom, 20)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: hotkey
                    default: done
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    if step > 0 {
                        Button("上一步") { withAnimation { step -= 1 } }.buttonStyle(.bordered)
                    }
                    Spacer()
                    if step < steps.count - 1 {
                        Button(step == 1 && !Permissions.allGranted ? "稍后再开，下一步" : "下一步") {
                            withAnimation { step += 1 }
                        }
                        .buttonStyle(.borderedProminent).tint(Brand.accent)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("开始使用") {
                            settings.hasCompletedOnboarding = true
                        }
                        .buttonStyle(.borderedProminent).tint(Brand.accent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(28)
            }
            .frame(width: 560, height: 420)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Brand.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 40, y: 16)
        }
        .onReceive(timer) { _ in tick += 1 }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("欢迎使用 Saycribe").font(.system(size: 24, weight: .semibold))
            Text("按住快捷键说话，松手后文字会写进当前窗口。整理、改口、列表、翻译都在本机识别 + 联网整理。")
                .font(.system(size: 13.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                tip("waveform", "按住说话，松手写入；点一下可免提")
                tip("character.cursor.ibeam", "选中文字后再说话 = 按你的指令改写")
                tip("globe", "按翻译组合键说话，直接出目标语言")
            }.padding(.top, 8)
            Spacer(minLength: 0)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("需要这三项权限").font(.system(size: 22, weight: .semibold))
            Text("都开了才能监听快捷键、录音和往窗口里写字。关掉后也会在设置里提醒你。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Card {
                PermissionRow(name: "麦克风", hint: "用来录音。", ok: Permissions.microphone) {
                    AudioRecorder.requestPermission { _ in }
                }
                RowDivider()
                PermissionRow(name: "辅助功能", hint: "用来把文字写进当前窗口、读选区。", ok: Permissions.accessibility) {
                    Permissions.open("Privacy_Accessibility")
                }
                RowDivider()
                PermissionRow(name: "输入监控", hint: "用来监听全局快捷键。", ok: Permissions.inputMonitoring) {
                    Permissions.open("Privacy_ListenEvent")
                }
            }
            Spacer(minLength: 0)
        }
        .id(tick) // refresh permission badges
    }

    private var hotkey: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("记住你的快捷键").font(.system(size: 22, weight: .semibold))
            Text("默认是右侧 ⌘（fn 也可在设置里改）。按住说话，松手结束；轻点一下进入免提，再点一下结束。")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Keycap(label: settings.hotkey.keycap)
                Text(settings.hotkey.label).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            if settings.translateCombo != .off {
                Text("翻译：按住 \(settings.translateCombo.label) + 录音键").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Text("之后可在「设置 → 快捷键」里改成任意组合，或点「录制…」自己按一次。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("可以开始了").font(.system(size: 22, weight: .semibold))
            Text("切到任意输入框，按住快捷键说一句话试试。整理记录会出现在「历史记录」；词典和个人 App 语气在侧边栏。")
                .font(.system(size: 13.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !Permissions.allGranted {
                Text("还有权限没开：可随时在设置页补开。").font(.system(size: 12.5)).foregroundStyle(Brand.accent)
            }
            Spacer(minLength: 0)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Brand.accent).frame(width: 22)
            Text(text).font(.system(size: 13))
        }
    }
}
