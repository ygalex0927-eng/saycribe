import Foundation

/// Splits a long 16 kHz mono recording into utterances with Silero VAD, then joins cleaned pieces.
enum Segmenter {
    /// Use VAD path when the recording is longer than this (seconds). Short clips stay on the fast single-pass path.
    static let longThresholdSeconds = 6.0

    /// Cuts the recording in the middle of the pauses VAD found, so no audio is dropped at segment edges
    /// (VAD's own segments trim speech tails). Falls back to `[samples]` when VAD finds < 2 utterances.
    static func split(_ samples: [Float], vad: VoiceDetector) -> [[Float]] {
        for start in stride(from: 0, to: samples.count, by: 1600) {
            _ = vad.accept(Array(samples[start..<min(start + 1600, samples.count)]))
        }
        _ = vad.flush()
        let cuts = cutPoints(vad.spans, total: samples.count)
        guard !cuts.isEmpty else { return [samples] }
        var out: [[Float]] = []
        var from = 0
        for c in cuts + [samples.count] { out.append(Array(samples[from..<c])); from = c }
        return out
    }

    /// Midpoints between consecutive speech spans (sorted, strictly inside 0…total).
    static func cutPoints(_ spans: [(start: Int, count: Int)], total: Int) -> [Int] {
        let s = spans.sorted { $0.start < $1.start }
        guard s.count >= 2 else { return [] }
        var cuts: [Int] = []
        for i in 1..<s.count {
            let end = s[i - 1].start + s[i - 1].count, next = s[i].start
            let c = next > end ? (end + next) / 2 : next
            if c > (cuts.last ?? 0), c < total { cuts.append(c) }
        }
        return cuts
    }

    /// One recognizer pass per VAD segment; `vadModel == nil` (or VAD failing to load) = single pass.
    static func transcribe(_ samples: [Float], recognizer: Recognizer, vadModel: URL?) -> [String] {
        guard let vadModel, let vad = VoiceDetector(model: vadModel, minSilence: 0.5) else { return [recognizer.transcribe(samples)] }
        return split(samples, vad: vad).map { recognizer.transcribe($0) }.filter { !$0.isEmpty }
    }

    /// Cleans pieces concurrently (keeps order). Pieces are grouped up to ~400 chars so each call has context.
    static func cleanAll(_ parts: [String], _ clean: @escaping (String) async throws -> String) async throws -> String {
        let groups = group(parts, limit: 400)
        let outs = try await withThrowingTaskGroup(of: (Int, String).self) { g in
            for (i, text) in groups.enumerated() { g.addTask { (i, try await clean(text)) } }
            var r = [String](repeating: "", count: groups.count)
            for try await (i, s) in g { r[i] = s }
            return r
        }
        return outs.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Packs consecutive pieces into chunks of at most `limit` characters (a single longer piece stays whole).
    static func group(_ parts: [String], limit: Int) -> [String] {
        var out: [String] = []
        var cur: [String] = []
        for p in parts where !p.isEmpty {
            if !cur.isEmpty && join(cur + [p]).count > limit { out.append(join(cur)); cur = [] }
            cur.append(p)
        }
        if !cur.isEmpty { out.append(join(cur)) }
        return out
    }

    /// Joins cleaned (or raw) segment texts. CJK runs abut; Latin words get a single space.
    static func join(_ parts: [String]) -> String {
        var out = ""
        for raw in parts {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if out.isEmpty { out = t; continue }
            if needsSpace(between: out, and: t) { out += " " }
            out += t
        }
        return out
    }

    private static func needsSpace(between a: String, and b: String) -> Bool {
        guard let x = a.last, let y = b.first else { return false }
        return x.isASCII && (x.isLetter || x.isNumber) && y.isASCII && (y.isLetter || y.isNumber)
    }
}
