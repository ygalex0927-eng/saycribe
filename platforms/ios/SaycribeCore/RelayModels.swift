import Foundation

// 协议 v1 / v1.1 的数据结构。全部字段可选或带默认值，未知字段由 JSONDecoder 自动忽略，兼容协议升级。

public struct RelayUsage: Decodable, Equatable {
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var cacheHitTokens: Int?
}

public struct RelayTiming: Decodable, Equatable {
    public var firstTokenMs: Int?
    public var upstreamMs: Int?
    public var totalMs: Int?
}

public struct RelayResult: Decodable, Equatable {
    public var text: String
    public var sessionId: String?
    public var seq: Int?
    public var model: String?
    public var promptVersion: String?
    public var usage: RelayUsage?
    public var timing: RelayTiming?

    enum CodingKeys: String, CodingKey { case text, sessionId, seq, model, promptVersion, usage, timing }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        sessionId = try? c.decodeIfPresent(String.self, forKey: .sessionId)
        seq = try? c.decodeIfPresent(Int.self, forKey: .seq)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        promptVersion = try? c.decodeIfPresent(String.self, forKey: .promptVersion)
        usage = try? c.decodeIfPresent(RelayUsage.self, forKey: .usage)
        timing = try? c.decodeIfPresent(RelayTiming.self, forKey: .timing)
    }
}

/// GET /v1/me 的结果；v1.1 起带 platform。
public struct RelayIdentity: Decodable, Equatable {
    public var tokenId: String?
    public var user: String?
    public var device: String?
    public var platform: String?
}

struct RelayErrorBody: Decodable {
    struct Inner: Decodable { var code: String?; var message: String? }
    var error: Inner?
}

/// 一次请求的公共字段。
public struct RelaySegment: Equatable {
    public var sessionId: String
    public var seq: Int
    public var isFinal: Bool
    public init(sessionId: String = UUID().uuidString, seq: Int = 0, isFinal: Bool = true) {
        self.sessionId = sessionId; self.seq = seq; self.isFinal = isFinal
    }
}

public enum RelayError: Error, Equatable {
    case badRequest(String?)
    case unauthorized
    case revoked
    case tooLarge
    case rateLimited
    case upstreamError
    case upstreamTimeout
    case unavailable
    case offline
    case missingToken
    case server(status: Int, code: String?, message: String?)
    case invalidResponse

    /// 给 HUD / 键盘显示的中文提示。
    public var userMessage: String {
        switch self {
        case .unauthorized, .revoked, .missingToken: return "请在设置里填写/重新获取 token"
        case .offline: return "需要联网"
        case .rateLimited: return "请求太频繁，请稍后重试"
        case .tooLarge: return "内容过长"
        case .upstreamError, .upstreamTimeout: return "整理服务暂时出错，请重试"
        case .unavailable: return "服务维护中"
        case .badRequest: return "请求格式错误"
        case .server, .invalidResponse: return "服务返回异常"
        }
    }

    var isRetryable: Bool { self == .upstreamError || self == .upstreamTimeout }

    static func from(status: Int, data: Data) -> RelayError {
        let body = try? JSONDecoder.relay.decode(RelayErrorBody.self, from: data)
        let code = body?.error?.code, msg = body?.error?.message
        switch (status, code) {
        case (_, "unauthorized"), (401, _): return .unauthorized
        case (_, "revoked"), (403, _): return .revoked
        case (_, "too_large"), (413, _): return .tooLarge
        case (_, "rate_limited"), (429, _): return .rateLimited
        case (_, "upstream_timeout"), (504, _): return .upstreamTimeout
        case (_, "upstream_error"), (502, _): return .upstreamError
        case (_, "unavailable"), (503, _): return .unavailable
        case (_, "bad_request"), (400, _): return .badRequest(msg)
        default: return .server(status: status, code: code, message: msg)
        }
    }

    static func from(urlError: Error) -> RelayError {
        if let e = urlError as? URLError {
            switch e.code {
            case .timedOut: return .upstreamTimeout
            default: return .offline
            }
        }
        return .offline
    }
}

extension JSONDecoder {
    static let relay: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
