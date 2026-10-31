import Foundation

/// 主 App 与键盘扩展共用的常量。
public enum SharedConstants {
    public static let appGroupID = "group.com.motomotos.saycribe"
    /// 运行时会在前面拼上 AppIdentifierPrefix（Team ID + "."）。
    public static let keychainGroupSuffix = "com.motomotos.saycribe.shared"
    public static let defaultRelayBaseURL = URL(string: "https://saycribe-api.motomotos.com")!
    public static let urlScheme = "saycribe"

    /// App Group 容器；拿不到或不可写时退回 Application Support/saycribe-shared。
    public static func sharedContainerURL(fileManager: FileManager = .default) -> URL {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            // 无 entitlements 时 iOS 仍可能返回路径，但目录不可写——探测后再用
            let probe = url.appendingPathComponent(".saycribe-writable-probe")
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                try Data([0x31]).write(to: probe, options: .atomic)
                try fileManager.removeItem(at: probe)
                return url
            } catch {
                // fall through
            }
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let fallback = base.appendingPathComponent("saycribe-shared", isDirectory: true)
        try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
