import Foundation

/// One-shot import of URL + token from `platforms/mac/.relay-tokens.env` (chmod 600, gitignored).
/// Never logs the token. Used when the keychain is empty or the base URL has never been set.
enum RelayBootstrap {
    static let defaultBaseURL = "https://saycribe-api.motomotos.com"
    static let platform = "mac"

    struct Values {
        var url: String?
        var token: String?
        var tokenId: String?
    }

    /// Finds the env file without printing its contents.
    static func envFileURL() -> URL? {
        var roots: [URL] = []
        if let repo = ProcessInfo.processInfo.environment["SUIKOU_REPO"], !repo.isEmpty {
            roots.append(URL(fileURLWithPath: repo, isDirectory: true))
        }
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        if let exec = Bundle.main.executableURL {
            var dir = exec.deletingLastPathComponent()
            for _ in 0..<8 {
                roots.append(dir)
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        let fm = FileManager.default
        var seen = Set<String>()
        for root in roots {
            let candidate = root.appendingPathComponent("platforms/mac/.relay-tokens.env")
            let path = candidate.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            if fm.isReadableFile(atPath: path) { return candidate }
        }
        return nil
    }

    static func loadFile() -> Values {
        guard let url = envFileURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return Values() }
        var out = Values()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            switch key {
            case "SAYCRIBE_RELAY_URL": out.url = val
            case "SAYCRIBE_TOKEN": out.token = val
            case "SAYCRIBE_TOKEN_ID": out.tokenId = val
            default: break
            }
        }
        return out
    }

    /// Fills empty Settings fields from the env file once; writes token into the keychain.
    @discardableResult
    static func applyIfNeeded(to settings: Settings) -> Bool {
        let file = loadFile()
        var changed = false
        if settings.relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.relayBaseURL = file.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? file.url! : defaultBaseURL
            changed = true
        }
        if settings.relayToken.isEmpty, let tok = file.token, !tok.isEmpty {
            settings.relayToken = tok
            changed = true
        }
        return changed
    }
}
