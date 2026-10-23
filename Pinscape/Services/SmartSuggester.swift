import Foundation
import NaturalLanguage

/// Guesses a place for a thought, entirely on device.
///
/// First the hand-tuned hints ("wood stain" → hardware store). When those find nothing,
/// Apple's on-device word embeddings judge which kind of place a word is closest to,
/// so "cinnamon" still lands on the supermarket and "grout" on the hardware store.
enum SmartSuggester {
    /// Cosine distance below which a word counts as related to a place.
    private static let threshold: Double = 0.82

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "get", "buy", "pick", "some", "more", "new", "that", "this", "one", "dark", "light",
        "remember", "ask", "about", "check", "try", "need", "call", "find", "look", "big", "small", "good", "nice",
    ]

    private static let embedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)

    static func suggestions(for note: String, market: Brand.Market, limit: Int = 4) -> [PlaceSuggestion] {
        let keyword = PlaceSuggester.suggestions(for: note, market: market, limit: limit)
        if !keyword.isEmpty { return keyword }
        return Array(embeddingSuggestions(for: note, market: market).prefix(limit))
    }

    private static func embeddingSuggestions(for note: String, market: Brand.Market) -> [PlaceSuggestion] {
        guard let embedding else { return [] }
        let words = TextNormalizer.tokens(note)
            .map(\.norm)
            .filter { $0.count >= 3 && !stopWords.contains($0) && embedding.contains($0) }
        guard !words.isEmpty else { return [] }

        var ranked: [(category: PlaceCategory, distance: Double, word: String)] = []
        for category in PlaceCategory.allCases where category.isSearchable {
            let anchors = anchorWords(for: category).filter { embedding.contains($0) }
            var best = (distance: Double.infinity, word: "")
            for word in words {
                for anchor in anchors {
                    let distance = embedding.distance(between: word, and: anchor)
                    if distance < best.distance {
                        best = (distance, word)
                    }
                }
            }
            if best.distance < threshold {
                ranked.append((category, best.distance, best.word))
            }
        }
        ranked.sort { $0.distance < $1.distance }

        var suggestions: [PlaceSuggestion] = []
        for entry in ranked.prefix(2) {
            if let brand = BrandCatalog.all.first(where: { $0.category == entry.category && $0.market == market }) {
                suggestions.append(PlaceSuggestion(kind: .brand(brand), reason: entry.word))
            }
            suggestions.append(PlaceSuggestion(kind: .category(entry.category), reason: entry.word))
        }
        return suggestions
    }

    /// Single words that stand for a kind of place: its own name plus its one-word hints.
    private static func anchorWords(for category: PlaceCategory) -> [String] {
        let phrases = category.itemHints + category.placeWords + [category.searchQuery]
        var words = Set<String>()
        for phrase in phrases {
            let tokens = TextNormalizer.tokens(phrase).map(\.norm)
            if tokens.count == 1, let word = tokens.first, word.count >= 3 {
                words.insert(word)
            }
        }
        return Array(words)
    }
}
