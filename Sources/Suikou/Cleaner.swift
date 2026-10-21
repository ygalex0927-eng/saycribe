import Foundation

/// Settings captured on the main thread when a dictation starts, so background work never reads live Settings.
struct LLMConfig {
    let apiKey: String
    let cleanModel: String
    let editModel: String
    let dictionary: [String]

    static func snapshot() -> LLMConfig {
        let s = Settings.shared
        return LLMConfig(apiKey: s.apiKey, cleanModel: s.cleanModel, editModel: s.editModel, dictionary: s.dictionary)
    }
}

/// Turns a raw transcript into the text the user meant to type, via DeepSeek (thinking disabled for latency).
final class Cleaner {
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    private let cleanPrompt: String
    private let editPrompt: String
    private let translatePrompt: String
    private let styles: [String: String]

    init(resources: URL) {
        let dir = resources.appendingPathComponent("prompts")
        cleanPrompt = (try? String(contentsOf: dir.appendingPathComponent("clean.md"), encoding: .utf8)) ?? ""
        editPrompt = (try? String(contentsOf: dir.appendingPathComponent("edit.md"), encoding: .utf8)) ?? ""
        translatePrompt = (try? String(contentsOf: dir.appendingPathComponent("translate.md"), encoding: .utf8)) ?? ""
        let data = (try? Data(contentsOf: dir.appendingPathComponent("styles.json"))) ?? Data()
        styles = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Opens the TLS connection while the user is still talking, so the real request skips the handshake.
    func warmUp(apiKey key: String) {
        guard !key.isEmpty else { return }
        var req = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: req).resume()
    }

    func clean(_ transcript: String, style: AppStyle, config: LLMConfig) async throws -> String {
        // Keep in sync with eval/run_eval.py build_user_msg
        var parts = [styles[style.rawValue] ?? ""]
        if !config.dictionary.isEmpty { parts.append("【个人词典】" + config.dictionary.joined(separator: "、")) }
        parts.append("<transcript>\(transcript)</transcript>")
        return try await complete(key: config.apiKey, model: config.cleanModel, system: cleanPrompt, user: parts.joined(separator: "\n"),
                                  timeout: 4 + Double(transcript.count) * 0.02)
    }

    func translate(_ transcript: String, direction: String, style: AppStyle, config: LLMConfig) async throws -> String {
        var parts = ["【翻译方向】\(direction)", styles[style.rawValue] ?? ""]
        if !config.dictionary.isEmpty { parts.append("【个人词典】" + config.dictionary.joined(separator: "、")) }
        parts.append("<transcript>\(transcript)</transcript>")
        return try await complete(key: config.apiKey, model: config.cleanModel, system: translatePrompt, user: parts.joined(separator: "\n"),
                                  timeout: 5 + Double(transcript.count) * 0.03)
    }

    func edit(selection: String, instruction: String, config: LLMConfig) async throws -> String {
        let user = "<selection>\(selection)</selection>\n<instruction>\(instruction)</instruction>"
        return try await complete(key: config.apiKey, model: config.editModel, system: editPrompt, user: user,
                                  timeout: 6 + Double(selection.count) * 0.03)
    }

    private func complete(key: String, model: String, system: String, user: String, timeout: TimeInterval) async throws -> String {
        guard !key.isEmpty else { throw CleanerError.noKey }
        var req = URLRequest(url: endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "thinking": ["type": "disabled"],
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw CleanerError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        struct Reply: Decodable {
            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            let choices: [Choice]
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return (reply.choices.first?.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CleanerError: LocalizedError {
    case noKey
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "未设置 DeepSeek API Key"
        case let .http(code, body): return "DeepSeek \(code): \(body.prefix(120))"
        }
    }
}
