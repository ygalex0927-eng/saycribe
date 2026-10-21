import Foundation

/// Cleans short utterances on-device so they can skip the DeepSeek round trip:
/// drops filler sounds, tidies spacing, and settles the trailing punctuation for the app's style.
/// It does not handle self-corrections or misheard terms — those need the model.
enum LocalCleaner {
    /// Fillers removed anywhere: pure hesitation sounds that never carry meaning.
    private static let fillerAnywhere = try! NSRegularExpression(pattern: "[嗯呃额唔]+[，,、]?")
    /// Fillers removed only at the start, where they're hesitation rather than content ("好啊" keeps its 啊).
    private static let fillerLeading = try! NSRegularExpression(pattern: "^(?:(?:啊|哦|那个|这个|就是说|就是|然后)[，,、 ]*)+")
    private static let englishFillers = try! NSRegularExpression(pattern: "\\b(?:um+|uh+|erm|hmm+)\\b[,]?\\s*", options: .caseInsensitive)
    private static let cjkLatinGap = try! NSRegularExpression(pattern: "(?<=[\\p{Han}])(?=[A-Za-z0-9])|(?<=[A-Za-z0-9])(?=[\\p{Han}])")

    static func clean(_ raw: String, style: AppStyle) -> String {
        var s = raw
        for re in [fillerAnywhere, fillerLeading, englishFillers] {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,、")))
        guard !s.isEmpty else { return "" }
        // Same spacing rule as the cleanup prompt: one space between Chinese and Latin letters/digits.
        s = cjkLatinGap.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")

        let hasCJK = s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        if !hasCJK, let first = s.first, first.isLowercase {
            s = first.uppercased() + s.dropFirst()
        }

        let terminal: Set<Character> = ["。", "！", "？", ".", "!", "?", "…"]
        let endsWithTerminal = s.last.map(terminal.contains) ?? false
        switch style {
        case .chat, .code:
            // Chat messages and prompts read better without a trailing full stop.
            if s.hasSuffix("。") || (s.hasSuffix(".") && !s.hasSuffix("..")) { s.removeLast() }
        case .email, .notes:
            if !endsWithTerminal { s += hasCJK ? "。" : "." }
        }
        return s
    }
}
