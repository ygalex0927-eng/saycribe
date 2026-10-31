import Foundation

/// Settings captured on the main thread when a dictation starts, so background work never reads live Settings.
struct LLMConfig {
    let relayToken: String
    let relayBaseURL: String
    let dictionary: [String]

    static func snapshot() -> LLMConfig {
        let s = Settings.shared
        return LLMConfig(relayToken: s.relayToken, relayBaseURL: s.relayBaseURL, dictionary: s.dictionary)
    }

    var baseURL: URL {
        let raw = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = raw.isEmpty ? RelayBootstrap.defaultBaseURL : raw
        return URL(string: s.hasSuffix("/") ? String(s.dropLast()) : s) ?? URL(string: RelayBootstrap.defaultBaseURL)!
    }
}

/// Turns a raw transcript into the text the user meant to type, via the Saycribe relay (docs/中转接口.md v1.1).
/// Prompts and model live on the server; the client only sends transcript / style / dictionary.
final class Cleaner {
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: cfg)
    }()

    /// Kept for call-site compatibility; prompts are no longer loaded locally.
    init(resources: URL) {}

    /// GET /v1/ping (no auth) so TLS + keep-alive are warm before the user releases the hotkey.
    func warmUp(baseURL: URL) {
        let url = baseURL.appendingPathComponent("v1/ping")
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "GET"
        session.dataTask(with: req).resume()
    }

    /// Public ping for Settings "测试连接" / selftest. Returns api_version or throws.
    func ping(baseURL: URL) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/ping")
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "GET"
        let (data, resp) = try await data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw CleanerError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, String(data: data, encoding: .utf8) ?? "")
        }
        struct Pong: Decodable { let ok: Bool?; let api_version: String? }
        let pong = try JSONDecoder().decode(Pong.self, from: data)
        return pong.api_version ?? "ok"
    }

    /// GET /v1/me — validates the device token.
    func me(config: LLMConfig) async throws -> (user: String, platform: String, device: String, tokenId: String) {
        guard !config.relayToken.isEmpty else { throw CleanerError.noToken }
        var req = URLRequest(url: config.baseURL.appendingPathComponent("v1/me"), timeoutInterval: 8)
        req.httpMethod = "GET"
        req.setValue("Bearer \(config.relayToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await data(for: req)
        try throwIfRelayError(data: data, resp: resp)
        struct Me: Decodable {
            let user: String?
            let platform: String?
            let device: String?
            let token_id: String?
        }
        let me = try JSONDecoder().decode(Me.self, from: data)
        return (me.user ?? "", me.platform ?? "", me.device ?? "", me.token_id ?? "")
    }

    func clean(_ transcript: String, style: AppStyle, config: LLMConfig,
               sessionId: String? = nil, seq: Int? = nil, context: String? = nil, final: Bool? = nil) async throws -> String {
        var body: [String: Any] = [
            "transcript": transcript,
            "style": style.rawValue,
            "stream": false,
        ]
        if !config.dictionary.isEmpty { body["dictionary"] = config.dictionary }
        if let sessionId { body["session_id"] = sessionId }
        if let seq { body["seq"] = seq }
        if let context, !context.isEmpty { body["context"] = context }
        if let final { body["final"] = final }
        return try await post(path: "v1/clean", body: body, config: config,
                              timeout: 4 + Double(transcript.count) * 0.02)
    }

    func translate(_ transcript: String, direction: String, style: AppStyle, config: LLMConfig) async throws -> String {
        var body: [String: Any] = [
            "transcript": transcript,
            "direction": direction,
            "style": style.rawValue,
            "stream": false,
        ]
        if !config.dictionary.isEmpty { body["dictionary"] = config.dictionary }
        return try await post(path: "v1/translate", body: body, config: config,
                              timeout: 5 + Double(transcript.count) * 0.03)
    }

    func interpret(_ transcript: String, context: [String], config: LLMConfig) async throws -> String {
        var body: [String: Any] = [
            "transcript": transcript,
            "stream": false,
        ]
        if !context.isEmpty { body["context"] = context }
        if !config.dictionary.isEmpty { body["dictionary"] = config.dictionary }
        return try await post(path: "v1/interpret", body: body, config: config,
                              timeout: 6 + Double(transcript.count) * 0.03)
    }

    func edit(selection: String, instruction: String, config: LLMConfig) async throws -> String {
        let body: [String: Any] = [
            "selection": selection,
            "instruction": instruction,
            "stream": false,
        ]
        return try await post(path: "v1/edit", body: body, config: config,
                              timeout: 6 + Double(selection.count) * 0.03)
    }

    // MARK: - HTTP

    private func post(path: String, body: [String: Any], config: LLMConfig, timeout: TimeInterval) async throws -> String {
        guard !config.relayToken.isEmpty else { throw CleanerError.noToken }
        var req = URLRequest(url: config.baseURL.appendingPathComponent(path), timeoutInterval: max(timeout, 5))
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.relayToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await data(for: req)
        try throwIfRelayError(data: data, resp: resp)
        struct Reply: Decodable { let text: String? }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return (reply.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func data(for req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch let err as URLError {
            throw mapURLError(err)
        } catch {
            if let urlErr = error as? URLError { throw mapURLError(urlErr) }
            // Nested URLError under Cancellation / NSError bridge
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain {
                throw CleanerError.offline
            }
            throw error
        }
    }

    private func mapURLError(_ err: URLError) -> CleanerError {
        switch err.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .timedOut,
             .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
            return .offline
        default:
            return .offline
        }
    }

    private func throwIfRelayError(data: Data, resp: URLResponse) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if code == 200 { return }
        struct ErrBody: Decodable {
            struct E: Decodable { let code: String?; let message: String? }
            let error: E?
        }
        let parsed = try? JSONDecoder().decode(ErrBody.self, from: data)
        let errCode = parsed?.error?.code ?? ""
        let message = parsed?.error?.message ?? (String(data: data, encoding: .utf8) ?? "")
        switch code {
        case 401, 403:
            throw CleanerError.unauthorized
        case 429:
            throw CleanerError.http(code, message.isEmpty ? "rate_limited" : message)
        case 502, 503, 504:
            throw CleanerError.http(code, message.isEmpty ? errCode : message)
        default:
            throw CleanerError.http(code, message.isEmpty ? errCode : message)
        }
    }
}

enum CleanerError: LocalizedError, Equatable {
    case noToken
    case unauthorized
    case offline
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noToken: return "请在设置里填写中转 token"
        case .unauthorized: return "请在设置里填写/重新获取 token"
        case .offline: return "需要联网"
        case let .http(code, body): return "中转 \(code): \(body.prefix(120))"
        }
    }

    /// True when the HUD should show exactly 「需要联网」.
    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }
}
