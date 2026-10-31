import Foundation

public struct SSEEvent: Equatable {
    public var event: String
    public var data: String
}

/// 逐行解析 text/event-stream。多行 data 用 \n 拼接；空行表示一个事件结束。
public struct SSEParser {
    private var event = ""
    private var dataLines: [String] = []

    public init() {}

    /// 喂一行（不含换行符）；遇到空行时返回完整事件。
    public mutating func feed(line raw: String) -> SSEEvent? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.isEmpty { return flush() }
        if line.hasPrefix(":") { return nil }
        let (field, value): (Substring, Substring)
        if let idx = line.firstIndex(of: ":") {
            field = line[..<idx]
            var v = line[line.index(after: idx)...]
            if v.hasPrefix(" ") { v = v.dropFirst() }
            value = v
        } else {
            field = Substring(line); value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": dataLines.append(String(value))
        default: break // id / retry / 未知字段忽略
        }
        return nil
    }

    /// 流结束时把残留事件吐出来。
    public mutating func flush() -> SSEEvent? {
        defer { event = ""; dataLines = [] }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: event.isEmpty ? "message" : event, data: dataLines.joined(separator: "\n"))
    }
}
