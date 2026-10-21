import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let app: String
    let raw: String
    let text: String
    let ms: Int
    var audioSeconds: Double? = nil
    /// "translate:<target id>" for translations; nil for plain dictation.
    var mode: String? = nil
}

final class History: ObservableObject {
    static let limit = 200
    @Published private(set) var entries: [HistoryEntry] = []
    private let url: URL

    init(url: URL = AppPaths.support.appendingPathComponent("history.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            entries = (try? dec.decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    func add(_ e: HistoryEntry) {
        entries.insert(e, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}

/// Lifetime totals shown on the home page. Kept separately from history so clearing history doesn't reset them.
final class Stats: ObservableObject {
    /// Average typing speed used for "time saved" (Chinese characters or English words per minute).
    static let typingPerMinute = 45.0

    @Published private(set) var words: Int
    @Published private(set) var audioSeconds: Double
    @Published private(set) var sessions: Int
    private let d = UserDefaults.standard

    init() {
        words = d.integer(forKey: "stat.words")
        audioSeconds = d.double(forKey: "stat.audioSeconds")
        sessions = d.integer(forKey: "stat.sessions")
    }

    func record(text: String, audioSeconds secs: Double) {
        words += Self.count(text)
        audioSeconds += secs
        sessions += 1
        d.set(words, forKey: "stat.words")
        d.set(audioSeconds, forKey: "stat.audioSeconds")
        d.set(sessions, forKey: "stat.sessions")
    }

    /// Speaking speed in words per minute.
    var wpm: Int { audioSeconds > 1 ? Int(Double(words) / (audioSeconds / 60)) : 0 }

    var minutesSaved: Int { max(0, Int(Double(words) / Self.typingPerMinute - audioSeconds / 60)) }

    /// Each CJK character counts as one word; runs of Latin letters/digits count as one word.
    static func count(_ text: String) -> Int {
        var n = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
                n += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { n += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return n
    }
}

enum AppPaths {
    static let support: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Suikou", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
