import SwiftUI
import SaycribeCore

@main
struct SaycribeMainApp: App {
    @StateObject private var session = DictationSession()
    @State private var showOnboarding = !ConfigStore.shared.onboardingDone
    @State private var showRecording = false

    var body: some Scene {
        WindowGroup {
            SettingsView()
                .environmentObject(session)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView {
                        ConfigStore.shared.onboardingDone = true
                        showOnboarding = false
                    }
                }
                .fullScreenCover(isPresented: $showRecording) {
                    RecordingView()
                        .environmentObject(session)
                }
                .onAppear {
                    #if DEBUG
                    let args = ProcessInfo.processInfo.arguments
                    let safe = args.map { $0.hasPrefix("sct_") ? "sct_***" : $0 }.joined(separator: "\n")
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let container = SharedConstants.sharedContainerURL()
                    let marker = docs.appendingPathComponent("launch-args.txt")
                    let dump = safe + "\n---\ncontainer=\(container.path)\n"
                    try? dump.write(to: marker, atomically: true, encoding: .utf8)
                    ConfigStore.shared.onboardingDone = true
                    showOnboarding = false
                    if let i = args.firstIndex(of: "-seedToken"), i + 1 < args.count {
                        let tok = args[i + 1]
                        // 无 keychain-access-groups 时默认组可能不可用：两边都写，读侧能命中其一
                        try? TokenStore(accessGroup: nil).save(tok)
                        try? TokenStore().save(tok)
                        let okNil = TokenStore(accessGroup: nil).load() != nil
                        let okDef = TokenStore().load() != nil
                        let probe = docs.appendingPathComponent("token-probe.txt")
                        try? "nilGroup=\(okNil) defaultGroup=\(okDef)\n".write(to: probe, atomically: true, encoding: .utf8)
                    }
                    if let i = args.firstIndex(of: "-seedRelayURL"), i + 1 < args.count,
                       let u = ConfigStore.normalizedURL(args[i + 1]) {
                        ConfigStore.shared.relayBaseURL = u
                    }
                    if args.contains("-autoRecordDemo") {
                        showRecording = true
                    }
                    if args.contains("-runFixturePipeline") {
                        showRecording = true
                        let wav = Bundle.main.url(forResource: "zh", withExtension: "wav")
                            ?? SharedConstants.sharedContainerURL().appendingPathComponent("fixture.wav")
                        Task { await session.runFixturePipeline(wavURL: wav) }
                    }
                    if args.contains("-runMicPipeline") {
                        showRecording = true
                        Task { await session.runMicPipeline(seconds: 2.5) }
                    }
                    #endif
                }
                .onOpenURL { url in
                    session.handle(url: url)
                    showRecording = true
                }
                .onChange(of: session.state) { _, s in
                    if s == .recording { showRecording = true }
                    if s == .idle && showRecording == false { /* keep */ }
                }
        }
    }
}
