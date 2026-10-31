import Foundation
import CryptoKit

/// 模型下载：断点续传（Range）+ sha256 校验。地址 / 大小 / 摘要可配置（以 docs/模型下载.md 为准）。
public final class ModelDownloader {
    public struct Spec: Equatable {
        public var urls: [URL]
        public var sha256: String
        public var expectedSize: Int64?
        public var fileName: String
        public init(urls: [URL], sha256: String, expectedSize: Int64? = nil, fileName: String) {
            self.urls = urls; self.sha256 = sha256.lowercased()
            self.expectedSize = expectedSize; self.fileName = fileName
        }
        /// 兼容旧单 URL 调用。
        public init(url: URL, sha256: String, expectedSize: Int64? = nil, fileName: String? = nil) {
            self.init(urls: [url], sha256: sha256, expectedSize: expectedSize, fileName: fileName ?? url.lastPathComponent)
        }
        public var url: URL { urls[0] }
    }

    public enum DownloadError: Error, Equatable {
        case http(Int)
        case checksumMismatch(expected: String, actual: String)
        case sizeMismatch(expected: Int64, actual: Int64)
        case network(String)
    }

    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public static func defaultDestination(fileName: String = "sensevoice.int8.onnx") -> URL {
        SharedConstants.sharedContainerURL().appendingPathComponent("models", isDirectory: true).appendingPathComponent(fileName)
    }

    /// 按 urls 依次尝试；中途失败留下 .part，下次断点续传。校验 sha256 通过后才改名。
    /// progress 回调参数：(已下载字节, 总字节 或 nil)。
    @discardableResult
    public func download(_ spec: Spec, to destination: URL,
                         progress: ((Int64, Int64?) -> Void)? = nil) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path), (try? Self.sha256(of: destination)) == spec.sha256 {
            return destination
        }
        var lastError: Error = DownloadError.network("no urls")
        for url in spec.urls {
            do {
                return try await downloadOne(Spec(urls: [url], sha256: spec.sha256, expectedSize: spec.expectedSize, fileName: spec.fileName),
                                             to: destination, progress: progress)
            } catch {
                lastError = error
                // 校验失败的 .part 已删；网络失败保留 .part 以便换源续传（同内容）。
            }
        }
        throw lastError
    }

    /// 把默认三件套下到 App Group 的 models/ 目录。
    public func ensureRequiredModels(progress: ((String, Int64, Int64?) -> Void)? = nil) async throws -> [URL] {
        let root = SharedConstants.sharedContainerURL().appendingPathComponent("models", isDirectory: true)
        var out: [URL] = []
        for spec in ModelDefaults.requiredFiles {
            let dest: URL
            if spec.fileName == ModelDefaults.sileroVAD.fileName {
                dest = root.appendingPathComponent(spec.fileName)
            } else {
                dest = root.appendingPathComponent(ModelDefaults.senseVoiceDirName, isDirectory: true).appendingPathComponent(spec.fileName)
            }
            let url = try await download(spec, to: dest) { done, total in progress?(spec.fileName, done, total) }
            out.append(url)
        }
        return out
    }

    private func downloadOne(_ spec: Spec, to destination: URL,
                             progress: ((Int64, Int64?) -> Void)?) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = destination.appendingPathExtension("part")
        if !fm.fileExists(atPath: part.path) { fm.createFile(atPath: part.path, contents: nil) }
        var offset = (try? fm.attributesOfItem(atPath: part.path)[.size] as? Int64) ?? 0

        var req = URLRequest(url: spec.url)
        req.timeoutInterval = 60
        if offset > 0 { req.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        let bytes: URLSession.AsyncBytes, resp: URLResponse
        do { (bytes, resp) = try await session.bytes(for: req) }
        catch { throw DownloadError.network(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw DownloadError.network("no http response") }

        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }
        switch http.statusCode {
        case 206: try handle.seek(toOffset: UInt64(offset))
        case 200:
            try handle.truncate(atOffset: 0); offset = 0
        case 416:
            break
        default: throw DownloadError.http(http.statusCode)
        }
        let total: Int64? = spec.expectedSize ?? (http.expectedContentLength > 0 ? http.expectedContentLength + offset : nil)

        if http.statusCode != 416 {
            var buffer = Data(); buffer.reserveCapacity(1 << 16)
            var written = offset
            do {
                for try await b in bytes {
                    buffer.append(b)
                    if buffer.count >= 1 << 16 {
                        try handle.write(contentsOf: buffer); written += Int64(buffer.count); buffer.removeAll(keepingCapacity: true)
                        progress?(written, total)
                    }
                }
            } catch {
                try? handle.write(contentsOf: buffer)
                throw DownloadError.network(error.localizedDescription)
            }
            try handle.write(contentsOf: buffer); written += Int64(buffer.count)
            progress?(written, total)
        }
        try handle.close()

        let size = (try fm.attributesOfItem(atPath: part.path)[.size] as? Int64) ?? 0
        if let exp = spec.expectedSize, exp != size {
            if size > exp { try? fm.removeItem(at: part) }
            throw DownloadError.sizeMismatch(expected: exp, actual: size)
        }
        let digest = try Self.sha256(of: part)
        guard digest == spec.sha256 else {
            try? fm.removeItem(at: part)
            throw DownloadError.checksumMismatch(expected: spec.sha256, actual: digest)
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: part, to: destination)
        return destination
    }

    /// 分块计算文件 sha256（十六进制小写），避免整个模型读进内存。
    public static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
