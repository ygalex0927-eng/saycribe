import XCTest
import CryptoKit
@testable import SaycribeCore

final class SSEParserTests: XCTestCase {
    func testMultilineAndCRLF() {
        var p = SSEParser()
        XCTAssertNil(p.feed(line: "event: delta\r"))
        XCTAssertNil(p.feed(line: "data: a"))
        XCTAssertNil(p.feed(line: "data: b"))
        XCTAssertNil(p.feed(line: "id: 7"))
        XCTAssertEqual(p.feed(line: ""), SSEEvent(event: "delta", data: "a\nb"))
        XCTAssertNil(p.feed(line: ""))
        XCTAssertNil(p.feed(line: "data:x"))
        XCTAssertEqual(p.flush(), SSEEvent(event: "message", data: "x"))
    }
}

final class ConfigStoreTests: XCTestCase {
    func testRelayURLConfigurable() {
        let d = UserDefaults(suiteName: "test.\(UUID())")!
        let s = ConfigStore(defaults: d)
        XCTAssertEqual(s.relayBaseURL.absoluteString, "https://saycribe-api.motomotos.com")
        s.relayBaseURL = ConfigStore.normalizedURL(" https://new.example.com/ ")!
        XCTAssertEqual(s.relayBaseURL.absoluteString, "https://new.example.com")
        XCTAssertNil(ConfigStore.normalizedURL("ftp://x")); XCTAssertNil(ConfigStore.normalizedURL("not a url"))
        d.set("garbage", forKey: ConfigStore.Key.relayBaseURL.rawValue)
        XCTAssertEqual(s.relayBaseURL, SharedConstants.defaultRelayBaseURL)
        XCTAssertEqual(s.style, "notes")
    }
}

final class TokenStoreTests: XCTestCase {
    func testFormat() {
        XCTAssertTrue(TokenStore.isPlausible("sct_abcDEF123-_xyz"))
        XCTAssertFalse(TokenStore.isPlausible("abc")); XCTAssertFalse(TokenStore.isPlausible("sct_ab cd efgh"))
    }

    func testRoundTrip() throws {
        let s = TokenStore(service: "test.\(UUID())", accessGroup: nil)
        do { try s.save("sct_firstTOKEN123") } catch TokenStore.TokenError.keychain(let st) {
            throw XCTSkip("keychain unavailable in this test host: \(st)")
        }
        XCTAssertEqual(s.load(), "sct_firstTOKEN123")
        try s.save("sct_secondTOKEN456"); XCTAssertEqual(s.load(), "sct_secondTOKEN456")
        XCTAssertThrowsError(try s.save("bad"))
        s.delete(); XCTAssertNil(s.load())
    }
}

final class IPCTests: XCTestCase {
    func testMailboxRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let box = SharedMailbox(directory: dir, notifier: nil)
        let cmd = KeyboardCommand(action: .start, sessionId: "s", timestamp: Date(timeIntervalSince1970: 1))
        try box.write(cmd, to: .keyboardCommand)
        XCTAssertEqual(box.read(KeyboardCommand.self, from: .keyboardCommand), cmd)
        let st = AppStatus(state: .done, sessionId: "s", text: "你好", revision: 3, timestamp: Date(timeIntervalSince1970: 2))
        try box.write(st, to: .appStatus)
        XCTAssertEqual(box.read(AppStatus.self, from: .appStatus), st)
        box.clear(.appStatus); XCTAssertNil(box.read(AppStatus.self, from: .appStatus))
        try? FileManager.default.removeItem(at: dir)
    }

    func testDarwinNotify() {
        let exp = expectation(description: "notified")
        let n = DarwinNotifier()
        let t = n.observe(.appStatus) { exp.fulfill() }
        n.post(.appStatus)
        wait(for: [exp], timeout: 2)
        n.remove(.appStatus, token: t)
    }
}

final class ModelDownloaderTests: XCTestCase {
    let payload: Data = Data((0..<200_000).map { UInt8($0 % 251) })
    var sha: String { SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined() }
    var dir: URL!

    override func setUp() {
        MockURLProtocol.reset()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func rangeHandler() -> (URLRequest) -> MockURLProtocol.Response {
        let p = payload
        return { req in
            if let r = req.value(forHTTPHeaderField: "Range"), let start = Int(r.dropFirst(6).dropLast()) {
                return .init(status: 206, headers: ["Content-Length": "\(p.count - start)"], body: p.subdata(in: start..<p.count))
            }
            return .init(status: 200, headers: ["Content-Length": "\(p.count)"], body: p)
        }
    }

    func testFreshDownload() async throws {
        MockURLProtocol.handler = rangeHandler()
        let dl = ModelDownloader(session: MockURLProtocol.session())
        let dest = dir.appendingPathComponent("m.onnx")
        _ = try await dl.download(.init(url: URL(string: "https://cdn.test/m")!, sha256: sha, expectedSize: Int64(payload.count)), to: dest)
        XCTAssertEqual(try Data(contentsOf: dest), payload)
        XCTAssertNil(MockURLProtocol.requests[0].value(forHTTPHeaderField: "Range"))
    }

    func testResume() async throws {
        MockURLProtocol.handler = rangeHandler()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("m.onnx")
        try payload.prefix(70_000).write(to: dest.appendingPathExtension("part"))
        let dl = ModelDownloader(session: MockURLProtocol.session())
        _ = try await dl.download(.init(url: URL(string: "https://cdn.test/m")!, sha256: sha.uppercased()), to: dest)
        XCTAssertEqual(MockURLProtocol.requests[0].value(forHTTPHeaderField: "Range"), "bytes=70000-")
        XCTAssertEqual(try Data(contentsOf: dest), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathExtension("part").path))
    }

    func testServerIgnoresRangeRestarts() async throws {
        let p = payload
        MockURLProtocol.handler = { _ in .init(status: 200, body: p) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("m.onnx")
        try Data(repeating: 9, count: 5000).write(to: dest.appendingPathExtension("part"))
        _ = try await ModelDownloader(session: MockURLProtocol.session()).download(.init(url: URL(string: "https://cdn.test/m")!, sha256: sha), to: dest)
        XCTAssertEqual(try Data(contentsOf: dest), payload)
    }

    func testChecksumMismatchDiscardsPart() async throws {
        MockURLProtocol.handler = rangeHandler()
        let dest = dir.appendingPathComponent("m.onnx")
        do {
            _ = try await ModelDownloader(session: MockURLProtocol.session()).download(.init(url: URL(string: "https://cdn.test/m")!, sha256: String(repeating: "0", count: 64)), to: dest)
            XCTFail()
        } catch ModelDownloader.DownloadError.checksumMismatch(_, let actual) {
            XCTAssertEqual(actual, sha)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathExtension("part").path))
    }

    func testHTTPError() async {
        MockURLProtocol.handler = { _ in .init(status: 404, body: Data()) }
        do {
            _ = try await ModelDownloader(session: MockURLProtocol.session()).download(.init(url: URL(string: "https://cdn.test/m")!, sha256: sha), to: dir.appendingPathComponent("m"))
            XCTFail()
        } catch { XCTAssertEqual(error as? ModelDownloader.DownloadError, .http(404)) }
    }

    func testAlreadyPresentSkipsNetwork() async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("m.onnx"); try payload.write(to: dest)
        _ = try await ModelDownloader(session: MockURLProtocol.session()).download(.init(url: URL(string: "https://cdn.test/m")!, sha256: sha), to: dest)
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }
}
