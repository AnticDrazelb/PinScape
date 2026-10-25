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
        var tokens: [Token] = []
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            let norm = normalize(raw)
            if norm.isEmpty {
                // A free-standing "—" isn't a word, but it belongs in the text: keep it on the word before.
                if let last = tokens.popLast() {
                    tokens.append(Token(original: last.original + " " + raw, norm: last.norm, endsClause: true))
                }
                continue
            }
            let endsClause = raw.last.map { ",:;".contains($0) } ?? false
            tokens.append(Token(original: String(raw), norm: norm, endsClause: endsClause))
        }
        return tokens
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
    /// An Apple Maps business name as a person would say it:
    /// "Boots Uk Limited - Birchwood Health Centre" → "Boots, Birchwood Health Centre".
    static func businessName(_ name: String) -> String {
        let parts = name.components(separatedBy: " - ")
            .map { withoutCompanySuffix($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? name : parts.joined(separator: ", ")
    }

    private static let companySuffixes: [[String]] = [["uk", "limited"], ["uk", "ltd"], ["limited"], ["ltd"], ["ltd."], ["plc"]]

    private static func withoutCompanySuffix(_ part: String) -> String {
        var words = part.split(separator: " ").map(String.init)
        var changed = true
        while changed {
            changed = false
            for suffix in companySuffixes where words.count > suffix.count && words.suffix(suffix.count).map({ $0.lowercased() }) == suffix {
                words.removeLast(suffix.count)
                changed = true
            }
        }
        return words.joined(separator: " ")
    }

    static func titleCase(_ text: String) -> String {
        text.split(separator: " ").map { word in
            guard let first = word.first, first.isLowercase else { return String(word) }
            return first.uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
