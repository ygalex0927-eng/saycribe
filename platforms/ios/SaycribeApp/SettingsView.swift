import SwiftUI
import SaycribeCore

struct SettingsView: View {
    @State private var relayURL = ConfigStore.shared.relayBaseURL.absoluteString
    @State private var tokenInput = ""
    @State private var hasToken = TokenStore().load() != nil
    @State private var testResult = ""
    @State private var testing = false
    @State private var showOnboarding = false
    @State private var showRecording = false
    @EnvironmentObject private var session: DictationSession
    private let styles = ["notes", "chat", "email", "code"]
    @State private var style = ConfigStore.shared.style

    var body: some View {
        NavigationStack {
            Form {
                Section("中转") {
                    TextField("中转地址", text: $relayURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(saveURL)
                    Button("恢复默认地址") { relayURL = SharedConstants.defaultRelayBaseURL.absoluteString; saveURL() }
                }
                Section {
                    SecureField(hasToken ? "已保存（输入新 token 可替换）" : "sct_…", text: $tokenInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("保存 token", action: saveToken).disabled(tokenInput.isEmpty)
                    if hasToken { Button("删除 token", role: .destructive) { TokenStore().delete(); hasToken = false } }
                } header: { Text("设备 token") } footer: { Text("token 只保存在本机钥匙串里，不会显示出来。") }
                Section {
                    Button(testing ? "正在测试…" : "测试连接", action: test).disabled(testing)
                    if !testResult.isEmpty { Text(testResult).font(.footnote) }
                }
                Section("整理语气") {
                    Picker("语气", selection: $style) { ForEach(styles, id: \.self) { Text($0) } }
                        .onChange(of: style) { _, v in ConfigStore.shared.style = v }
                }
                Section("模型") {
                    Text("识别模型会在首次使用时下载（地址待配置）。").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("使用引导") { showOnboarding = true }
                    Button("试一下录音") { showRecording = true }
                }
            }
            .navigationTitle("Saycribe")
            .sheet(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
            .fullScreenCover(isPresented: $showRecording) {
                RecordingView().environmentObject(session)
            }
        }
    }

    private func saveURL() {
        if let u = ConfigStore.normalizedURL(relayURL) { ConfigStore.shared.relayBaseURL = u; relayURL = u.absoluteString; testResult = "" }
        else { testResult = "地址格式不对，需要 https:// 开头" }
    }

    private func saveToken() {
        do { try TokenStore().save(tokenInput); tokenInput = ""; hasToken = true; testResult = "token 已保存" }
        catch { testResult = "token 格式不对（应以 sct_ 开头）" }
    }

    private func test() {
        saveURL(); testing = true; testResult = ""
        Task {
            let client = RelayClient()
            let reachable = await client.ping()
            if !reachable { testResult = "连不上中转（需要联网，或地址不对）"; testing = false; return }
            do {
                let me = try await client.me()
                testResult = "连接正常：\(me.user ?? "?") / \(me.device ?? "?")\(me.platform.map { " / \($0)" } ?? "")"
            } catch let e as RelayError { testResult = e.userMessage } catch { testResult = "测试失败" }
            testing = false
        }
    }
}
