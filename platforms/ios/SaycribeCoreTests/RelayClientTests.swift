import XCTest
@testable import SaycribeCore

final class RelayClientTests: XCTestCase {
    var client: RelayClient!
    let base = URL(string: "https://relay.test")!

    override func setUp() {
        MockURLProtocol.reset()
        client = RelayClient(session: MockURLProtocol.session(), baseURL: { [base] in base }, token: { "sct_TESTTOKENabcdef_-" })
        client.retryDelay = 0
    }

    func json(_ status: Int, _ s: String) -> MockURLProtocol.Response { .init(status: status, headers: ["Content-Type": "application/json"], body: Data(s)) }

    func testTimeoutFormula() {
        XCTAssertEqual(RelayClient.timeout(forCharacters: 0), 4)
        XCTAssertEqual(RelayClient.timeout(forCharacters: 100), 6, accuracy: 0.0001)
    }

    func testPing() async {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/v1/ping")
            XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
            return self.json(200, #"{"ok":true}"#)
        }
        let ok = await client.ping()
        XCTAssertTrue(ok)
    }

    func testCleanRequestShapeAndUnknownFields() async throws {
        MockURLProtocol.handler = { _ in self.json(200, #"{"text":"整理后","session_id":"s1","seq":2,"model":"m","prompt_version":"2026-10-30","usage":{"prompt_tokens":1,"new_field":5},"timing":{"total_ms":10},"platform":"ios","future":{"x":[1,2]}}"#) }
        let ctx = String(repeating: "啊", count: 400)
        let r = try await client.clean(transcript: "原文", style: "chat", dictionary: ["Saycribe"], context: ctx,
                                       segment: RelaySegment(sessionId: "s1", seq: 2, isFinal: true))
        XCTAssertEqual(r.text, "整理后"); XCTAssertEqual(r.seq, 2); XCTAssertEqual(r.promptVersion, "2026-10-30")
        XCTAssertEqual(r.usage?.promptTokens, 1); XCTAssertEqual(r.timing?.totalMs, 10)
        let req = MockURLProtocol.requests[0]
        XCTAssertEqual(req.httpMethod, "POST"); XCTAssertEqual(req.url?.absoluteString, "https://relay.test/v1/clean")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sct_TESTTOKENabcdef_-")
        XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")!.contains("application/json"))
        XCTAssertEqual(req.timeoutInterval, 4.04, accuracy: 0.001)
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["transcript"] as? String, "原文"); XCTAssertEqual(body["style"] as? String, "chat")
        XCTAssertEqual(body["session_id"] as? String, "s1"); XCTAssertEqual(body["seq"] as? Int, 2)
        XCTAssertEqual(body["final"] as? Bool, true); XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual((body["context"] as? String)?.count, 300)
        XCTAssertEqual(body["dictionary"] as? [String], ["Saycribe"])
    }

    func testEmptyTextAllowed() async throws {
        MockURLProtocol.handler = { _ in self.json(200, #"{"text":""}"#) }
        let r = try await client.clean(transcript: "嗯")
        XCTAssertEqual(r.text, "")
    }

    func testMeWithPlatform() async throws {
        MockURLProtocol.handler = { _ in self.json(200, #"{"token_id":"t_1","user":"zjh","device":"iphone","platform":"ios","extra":1}"#) }
        let me = try await client.me()
        XCTAssertEqual(me, RelayIdentity(tokenId: "t_1", user: "zjh", device: "iphone", platform: "ios"))
    }

    func testErrorMapping() async {
        let cases: [(Int, String, RelayError)] = [
            (400, "bad_request", .badRequest("m")), (401, "unauthorized", .unauthorized), (403, "revoked", .revoked),
            (413, "too_large", .tooLarge), (429, "rate_limited", .rateLimited), (503, "unavailable", .unavailable),
            (500, "weird", .server(status: 500, code: "weird", message: "m")),
        ]
        for (status, code, expected) in cases {
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _ in self.json(status, #"{"error":{"code":"\#(code)","message":"m"}}"#) }
            do { _ = try await client.clean(transcript: "x"); XCTFail("should throw") }
            catch { XCTAssertEqual(error as? RelayError, expected, "\(status)") }
            XCTAssertEqual(MockURLProtocol.requests.count, 1, "no retry for \(status)")
        }
    }

    func testRetryOnceOn502ThenSuccess() async throws {
        var n = 0
        MockURLProtocol.handler = { _ in n += 1; return n == 1 ? self.json(502, #"{"error":{"code":"upstream_error"}}"#) : self.json(200, #"{"text":"ok"}"#) }
        let r = try await client.clean(transcript: "x")
        XCTAssertEqual(r.text, "ok"); XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    func testRetryOnlyOnceOn504() async {
        MockURLProtocol.handler = { _ in self.json(504, #"{"error":{"code":"upstream_timeout"}}"#) }
        do { _ = try await client.clean(transcript: "x"); XCTFail() }
        catch { XCTAssertEqual(error as? RelayError, .upstreamTimeout) }
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    func testOffline() async {
        MockURLProtocol.handler = { _ in .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet)) }
        do { _ = try await client.clean(transcript: "x"); XCTFail() }
        catch { XCTAssertEqual(error as? RelayError, .offline); XCTAssertEqual((error as? RelayError)?.userMessage, "需要联网") }
    }

    func testMissingToken() async {
        let c = RelayClient(session: MockURLProtocol.session(), baseURL: { [base] in base }, token: { nil })
        do { _ = try await c.clean(transcript: "x"); XCTFail() }
        catch { XCTAssertEqual(error as? RelayError, .missingToken) }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testStreamDeltaAndDone() async throws {
        let sse = "event: delta\ndata: {\"text\":\"整理\"}\n\n: comment\nevent: delta\ndata: {\"text\":\"后\"}\n\nevent: unknown\ndata: {}\n\nevent: done\ndata: {\"text\":\"整理后的文字\",\"seq\":0,\"timing\":{\"first_token_ms\":420}}\n\n"
        MockURLProtocol.handler = { _ in .init(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(sse)) }
        var deltas: [String] = []
        let r = try await client.cleanStream(transcript: "x") { deltas.append($0) }
        XCTAssertEqual(deltas, ["整理", "后"]); XCTAssertEqual(r.text, "整理后的文字"); XCTAssertEqual(r.timing?.firstTokenMs, 420)
        let body = try JSONSerialization.jsonObject(with: MockURLProtocol.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testStreamErrorEvent() async {
        let sse = "event: error\ndata: {\"error\":{\"code\":\"upstream_timeout\",\"message\":\"t\"}}\n\n"
        var n = 0
        MockURLProtocol.handler = { _ in n += 1; return .init(status: 200, body: Data(sse)) }
        do { _ = try await client.cleanStream(transcript: "x") { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? RelayError, .upstreamTimeout) }
        XCTAssertEqual(n, 2) // 未收到 delta，重试一次
    }

    func testStreamNoRetryAfterDelta() async {
        let sse = "event: delta\ndata: {\"text\":\"半\"}\n\nevent: error\ndata: {\"error\":{\"code\":\"upstream_error\"}}\n\n"
        MockURLProtocol.handler = { _ in .init(status: 200, body: Data(sse)) }
        do { _ = try await client.cleanStream(transcript: "x") { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? RelayError, .upstreamError) }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testStreamHTTPError() async {
        MockURLProtocol.handler = { _ in self.json(401, #"{"error":{"code":"unauthorized"}}"#) }
        do { _ = try await client.cleanStream(transcript: "x") { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? RelayError, .unauthorized) }
    }

    func testStreamWithoutDoneIsInvalid() async {
        MockURLProtocol.handler = { _ in .init(status: 200, body: Data("event: delta\ndata: {\"text\":\"a\"}\n\n")) }
        do { _ = try await client.cleanStream(transcript: "x") { _ in }; XCTFail() }
        catch { XCTAssertEqual(error as? RelayError, .invalidResponse) }
    }

    func testEditAndTranslate() async throws {
        MockURLProtocol.handler = { _ in self.json(200, #"{"text":"r"}"#) }
        _ = try await client.edit(selection: "a", instruction: "b")
        _ = try await client.translate(transcript: "你好", direction: "中文→英文")
        XCTAssertEqual(MockURLProtocol.requests.map { $0.url!.path }, ["/v1/edit", "/v1/translate"])
    }
}
