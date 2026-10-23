import Foundation

/// A word from a capture, with its normalised form for matching.
struct Token: Equatable {
    /// The word as written, punctuation included.
    let original: String
    /// Lowercased, accent-folded, apostrophes and punctuation removed. "Sainsbury's," → "sainsburys".
    let norm: String
    /// The word ended a clause: "Tesco," or "B&Q:".
    let endsClause: Bool

    var startsWithCapital: Bool {
        original.first(where: { $0.isLetter })?.isUppercase ?? false
    }
}

enum TextNormalizer {
    /// Normalises one word for matching.
    static func normalize(_ word: some StringProtocol) -> String {
        let folded = String(word).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var out = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber || ch == "&" {
                out.append(ch)
            }
            // apostrophes, hyphens and other punctuation are dropped: "co-op" → "coop", "i'm" → "im"
        }
        return out
    }

    static func tokens(_ text: some StringProtocol) -> [Token] {
        text.split(whereSeparator: { $0.isWhitespace }).compactMap { raw in
            let norm = normalize(raw)
            let endsClause = raw.last.map { ",:;".contains($0) } ?? false
            if norm.isEmpty {
                // A free-standing "-" or "—" is punctuation, not a word.
                return nil
            }
            return Token(original: String(raw), norm: norm, endsClause: endsClause)
        }
    }

    /// The matching key for a phrase: normalised words joined by single spaces.
    static func key(_ phrase: some StringProtocol) -> String {
        tokens(phrase).map(\.norm).joined(separator: " ")
    }

    static func key(_ tokens: some Sequence<Token>) -> String {
        tokens.map(\.norm).joined(separator: " ")
    }

    /// Every spelling of a phrase a person might dictate or type.
    /// "B&Q" → ["b&q", "b & q", "b and q"]; "Marks and Spencer" → ["marks and spencer", "marks & spencer"].
    static func keyVariants(of phrase: String) -> [String] {
        var variants: [[String]] = [[]]
        for token in tokens(phrase) {
            var options: [[String]] = [[token.norm]]
            if token.norm == "&" {
                options = [["&"], ["and"]]
            } else if token.norm == "and" {
                options = [["and"], ["&"]]
            } else if token.norm.contains("&") {
                let parts = token.norm.split(separator: "&", omittingEmptySubsequences: true).map(String.init)
                if parts.count >= 2 {
                    options.append(Array(parts.map { [$0] }.joined(separator: ["&"])))
                    options.append(Array(parts.map { [$0] }.joined(separator: ["and"])))
                }
            }
            variants = variants.flatMap { prefix in options.map { prefix + $0 } }
        }
        var seen = Set<String>()
        return variants.map { $0.joined(separator: " ") }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Words that sit between a thought and a place and should be dropped from both.
    static let articles: Set<String> = ["the", "a", "an", "any", "my", "our", "some", "that", "this"]

    /// Capitalises the first letter, leaving the rest as written.
    static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Words that look like a title: "Bristol", "Mum's House".
    static func titleCase(_ text: String) -> String {
        text.split(separator: " ").map { word in
            guard let first = word.first, first.isLowercase else { return String(word) }
            return first.uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
