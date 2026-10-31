import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void
    var body: some View {
        NavigationStack {
            List {
                step(1, "添加键盘", "打开 设置 → 通用 → 键盘 → 键盘 → 添加新键盘，选择 Saycribe。")
                step(2, "允许完全访问", "在键盘列表里点 Saycribe，打开“允许完全访问”。键盘需要它来联网和与本 App 共享结果；Saycribe 不会记录你的按键。")
                step(3, "填写 token", "回到本 App 设置页，填写中转地址和设备 token，点“测试连接”。")
                step(4, "开始说话", "在任何输入框切换到 Saycribe 键盘，点麦克风。首次会跳到本 App 开始录音，然后返回原来的 App 继续说。")
                Section {
                    Button("打开系统设置") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                }
            }
            .navigationTitle("使用引导")
            .toolbar { Button("完成", action: onDone) }
        }
    }
    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(n). \(title)").font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
