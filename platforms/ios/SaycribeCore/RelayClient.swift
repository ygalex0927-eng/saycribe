import Foundation

/// 中转客户端，按 docs/中转接口.md v1 实现（兼容 v1.1 新增字段）。
public final class RelayClient {
    public typealias TokenProvider = () -> String?

    private let session: URLSession
    private let baseURLProvider: () -> URL
    private let tokenProvider: TokenProvider
    /// 502/504 时的重试次数（协议要求 1 次）。
    public var maxRetries = 1
    /// 重试前等待，测试里可设为 0。
    public var retryDelay: TimeInterval = 0.3

    public init(session: URLSession? = nil,
                baseURL: @escaping () -> URL = { ConfigStore.shared.relayBaseURL },
                token: @escaping TokenProvider = {
                    TokenStore().load() ?? TokenStore(accessGroup: nil).load()
                }) {
        self.session = session ?? RelayClient.makeSession()
        self.baseURLProvider = baseURL
        self.tokenProvider = token
    }

    /// 连接超时约 3s（URLSession 无独立连接超时，用空闲超时近似）；keep-alive 由 URLSession 复用。
    public static func makeSession() -> URLSession {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 3
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }

    /// 整体超时：4 + 字数×0.02 秒。
    public static func timeout(forCharacters n: Int) -> TimeInterval { 4 + Double(n) * 0.02 }

    // MARK: - 公共接口

    /// GET /v1/ping：无需鉴权，按下录音键时调用以预热连接。
    public func ping() async -> Bool {
        var req = URLRequest(url: endpoint("/v1/ping"))
        req.timeoutInterval = 3
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        struct Ping: Decodable { var ok: Bool? }
        return (try? JSONDecoder.relay.decode(Ping.self, from: data))?.ok ?? false
    }

    /// GET /v1/me：设置页“测试连接”。
    public func me() async throws -> RelayIdentity {
        let req = try authorizedRequest(path: "/v1/me", method: "GET", body: nil, timeout: 4)
        let data = try await send(req)
        guard let id = try? JSONDecoder.relay.decode(RelayIdentity.self, from: data) else { throw RelayError.invalidResponse }
        return id
    }

    /// POST /v1/clean 非流式。
    public func clean(transcript: String, style: String? = nil, dictionary: [String]? = nil,
                      context: String? = nil, segment: RelaySegment = RelaySegment()) async throws -> RelayResult {
        let body = cleanBody(transcript: transcript, style: style, dictionary: dictionary, context: context, segment: segment, stream: false)
        let req = try authorizedRequest(path: "/v1/clean", method: "POST", body: body,
                                        timeout: RelayClient.timeout(forCharacters: transcript.count))
        let data = try await send(req)
        guard let r = try? JSONDecoder.relay.decode(RelayResult.self, from: data) else { throw RelayError.invalidResponse }
        return r
    }

    /// POST /v1/clean 流式（SSE）。onDelta 收到增量；返回 done 的最终结果。
    public func cleanStream(transcript: String, style: String? = nil, dictionary: [String]? = nil,
                            context: String? = nil, segment: RelaySegment = RelaySegment(),
                            onDelta: @escaping (String) -> Void) async throws -> RelayResult {
        let body = cleanBody(transcript: transcript, style: style, dictionary: dictionary, context: context, segment: segment, stream: true)
        let req = try authorizedRequest(path: "/v1/clean", method: "POST", body: body,
                                        timeout: RelayClient.timeout(forCharacters: transcript.count))
        return try await stream(req, onDelta: onDelta)
    }

    /// POST /v1/edit 改写选区。
    public func edit(selection: String, instruction: String) async throws -> RelayResult {
        let body: [String: Any] = ["selection": selection, "instruction": instruction]
        let req = try authorizedRequest(path: "/v1/edit", method: "POST", body: body,
                                        timeout: RelayClient.timeout(forCharacters: selection.count + instruction.count))
        let data = try await send(req)
        guard let r = try? JSONDecoder.relay.decode(RelayResult.self, from: data) else { throw RelayError.invalidResponse }
        return r
    }

    /// POST /v1/translate。
    public func translate(transcript: String, direction: String, style: String? = nil, dictionary: [String]? = nil) async throws -> RelayResult {
        var body: [String: Any] = ["transcript": transcript, "direction": direction]
        if let style { body["style"] = style }
        if let dictionary, !dictionary.isEmpty { body["dictionary"] = dictionary }
        let req = try authorizedRequest(path: "/v1/translate", method: "POST", body: body,
                                        timeout: RelayClient.timeout(forCharacters: transcript.count))
        let data = try await send(req)
        guard let r = try? JSONDecoder.relay.decode(RelayResult.self, from: data) else { throw RelayError.invalidResponse }
        return r
    }

    // MARK: - 内部

    func endpoint(_ path: String) -> URL {
        URL(string: baseURLProvider().absoluteString + path)!
    }

    func cleanBody(transcript: String, style: String?, dictionary: [String]?, context: String?,
                   segment: RelaySegment, stream: Bool) -> [String: Any] {
        var b: [String: Any] = ["transcript": transcript, "session_id": segment.sessionId,
                                "seq": segment.seq, "final": segment.isFinal, "stream": stream]
        if let style { b["style"] = style }
        if let dictionary, !dictionary.isEmpty { b["dictionary"] = dictionary }
        if let context, !context.isEmpty { b["context"] = String(context.suffix(300)) }
        return b
    }

    func authorizedRequest(path: String, method: String, body: [String: Any]?, timeout: TimeInterval) throws -> URLRequest {
        guard let token = tokenProvider(), !token.isEmpty else { throw RelayError.missingToken }
        var req = URLRequest(url: endpoint(path))
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return req
    }

    /// 非流式请求，带 502/504 重试。
    func send(_ req: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await sendOnce(req)
            } catch let e as RelayError where e.isRetryable && attempt < maxRetries {
                attempt += 1
                if retryDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1e9)) }
            }
        }
    }

    private func sendOnce(_ req: URLRequest) async throws -> Data {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw RelayError.from(urlError: error) }
        guard let http = resp as? HTTPURLResponse else { throw RelayError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw RelayError.from(status: http.statusCode, data: data) }
        return data
    }

    /// 流式请求。只在还没收到任何 delta 时重试，避免重复输出。
    func stream(_ req: URLRequest, onDelta: @escaping (String) -> Void) async throws -> RelayResult {
        var attempt = 0
        while true {
            var gotDelta = false
            do {
                return try await streamOnce(req) { gotDelta = true; onDelta($0) }
            } catch let e as RelayError where e.isRetryable && attempt < maxRetries && !gotDelta {
                attempt += 1
                if retryDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1e9)) }
            }
        }
    }

    private func streamOnce(_ req: URLRequest, onDelta: (String) -> Void) async throws -> RelayResult {
        let bytes: URLSession.AsyncBytes, resp: URLResponse
        do { (bytes, resp) = try await session.bytes(for: req) }
        catch { throw RelayError.from(urlError: error) }
        guard let http = resp as? HTTPURLResponse else { throw RelayError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            var data = Data()
            do { for try await b in bytes { data.append(b) } } catch {}
            throw RelayError.from(status: http.statusCode, data: data)
        }
        var parser = SSEParser()
        var accumulated = ""
        func handle(_ ev: SSEEvent) throws -> RelayResult? {
            let data = Data(ev.data.utf8)
            switch ev.event {
            case "delta":
                struct D: Decodable { var text: String? }
                if let t = (try? JSONDecoder.relay.decode(D.self, from: data))?.text, !t.isEmpty {
                    accumulated += t; onDelta(t)
                }
            case "done":
                guard let r = try? JSONDecoder.relay.decode(RelayResult.self, from: data) else { throw RelayError.invalidResponse }
                return r
            case "error":
                let body = try? JSONDecoder.relay.decode(RelayErrorBody.self, from: data)
                throw RelayError.from(status: 0, code: body?.error?.code, message: body?.error?.message)
            default: break // 未知事件忽略（向前兼容）
            }
            return nil
        }
        do {
            // 不用 bytes.lines：它会吞掉空行，而空行是 SSE 事件分隔符。
            var buf = Data()
            for try await b in bytes {
                if b == 0x0A {
                    let line = String(decoding: buf, as: UTF8.self); buf.removeAll(keepingCapacity: true)
                    if let ev = parser.feed(line: line), let r = try handle(ev) { return r }
                } else { buf.append(b) }
            }
            if !buf.isEmpty, let ev = parser.feed(line: String(decoding: buf, as: UTF8.self)), let r = try handle(ev) { return r }
            if let ev = parser.flush(), let r = try handle(ev) { return r }
        } catch let e as RelayError { throw e }
        catch { throw RelayError.from(urlError: error) }
        _ = accumulated
        throw RelayError.invalidResponse // 流结束但没有 done
    }
}

extension RelayError {
    static func from(status: Int, code: String?, message: String?) -> RelayError {
        var obj: [String: Any] = [:]
        if let code { obj["code"] = code }
        if let message { obj["message"] = message }
        let data = (try? JSONSerialization.data(withJSONObject: ["error": obj])) ?? Data()
        return from(status: status, data: data)
    }
}
