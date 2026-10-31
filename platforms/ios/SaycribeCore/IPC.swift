import Foundation

/// 键盘 ↔ 主 App 通信：Darwin notify 只做“有新消息”信号，内容写在 App Group 共享文件里。
public enum IPCName: String {
    case keyboardCommand = "com.motomotos.saycribe.ipc.command"
    case appStatus = "com.motomotos.saycribe.ipc.status"
}

/// 键盘发给主 App 的指令。
public struct KeyboardCommand: Codable, Equatable {
    public enum Action: String, Codable { case start, stop, cancel }
    public var action: Action
    public var sessionId: String
    public var timestamp: Date
    public init(action: Action, sessionId: String = UUID().uuidString, timestamp: Date = Date()) {
        self.action = action; self.sessionId = sessionId; self.timestamp = timestamp
    }
}

/// 主 App 发给键盘的状态 / 结果。
public struct AppStatus: Codable, Equatable {
    public enum State: String, Codable { case idle, recording, recognizing, cleaning, done, error }
    public var state: State
    public var sessionId: String?
    public var text: String?
    public var message: String?
    /// 单调递增，键盘据此判断是否已插入过（避免重复插入）。
    public var revision: Int
    public var timestamp: Date
    public init(state: State, sessionId: String? = nil, text: String? = nil, message: String? = nil,
                revision: Int, timestamp: Date = Date()) {
        self.state = state; self.sessionId = sessionId; self.text = text; self.message = message
        self.revision = revision; self.timestamp = timestamp
    }
}

public final class DarwinNotifier {
    public static let shared = DarwinNotifier()
    private var handlers: [String: [UUID: () -> Void]] = [:]
    private let lock = NSLock()

    public func post(_ name: IPCName) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name.rawValue as CFString), nil, nil, true)
    }

    /// 注册观察者；返回的 token 用于取消。回调在主线程。
    @discardableResult
    public func observe(_ name: IPCName, handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        let first = handlers[name.rawValue] == nil
        handlers[name.rawValue, default: [:]][id] = handler
        lock.unlock()
        if first {
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, obs, cfName, _, _ in
                guard let obs, let cfName else { return }
                let me = Unmanaged<DarwinNotifier>.fromOpaque(obs).takeUnretainedValue()
                me.fire(cfName.rawValue as String)
            }, name.rawValue as CFString, nil, .deliverImmediately)
        }
        return id
    }

    public func remove(_ name: IPCName, token: UUID) {
        lock.lock(); handlers[name.rawValue]?[token] = nil; lock.unlock()
    }

    func fire(_ name: String) {
        lock.lock(); let hs = Array((handlers[name] ?? [:]).values); lock.unlock()
        DispatchQueue.main.async { hs.forEach { $0() } }
    }
}

/// 共享文件信箱：原子写 JSON。
public final class SharedMailbox {
    private let directory: URL
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }()
    private let notifier: DarwinNotifier?

    public init(directory: URL = SharedConstants.sharedContainerURL().appendingPathComponent("ipc", isDirectory: true),
                notifier: DarwinNotifier? = .shared) {
        self.directory = directory
        self.notifier = notifier
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(_ name: IPCName) -> URL { directory.appendingPathComponent(name.rawValue + ".json") }

    public func write<T: Encodable>(_ value: T, to name: IPCName) throws {
        let data = try encoder.encode(value)
        try data.write(to: url(name), options: .atomic)
        notifier?.post(name)
    }

    public func read<T: Decodable>(_ type: T.Type, from name: IPCName) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    public func clear(_ name: IPCName) { try? FileManager.default.removeItem(at: url(name)) }
}
