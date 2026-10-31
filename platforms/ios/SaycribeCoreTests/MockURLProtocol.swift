import Foundation

/// 拦截所有请求，由测试按顺序给出响应。
final class MockURLProtocol: URLProtocol {
    struct Response { var status: Int; var headers: [String: String] = [:]; var body: Data; var error: URLError? = nil }
    static var handler: ((URLRequest) -> Response)?
    static var requests: [URLRequest] = []
    static let lock = NSLock()

    static func reset() { lock.lock(); handler = nil; requests = []; lock.unlock() }

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: c)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var req = request
        if req.httpBody == nil, let s = req.httpBodyStream { // URLSession 会把 body 变成 stream
            s.open(); var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            s.close(); req.httpBody = d
        }
        MockURLProtocol.lock.lock(); MockURLProtocol.requests.append(req); let h = MockURLProtocol.handler; MockURLProtocol.lock.unlock()
        guard let r = h?(req) else { client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return }
        if let e = r.error { client?.urlProtocol(self, didFailWithError: e); return }
        let resp = HTTPURLResponse(url: req.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension Data { init(_ s: String) { self = s.data(using: .utf8)! } }
