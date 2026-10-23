import Foundation

/// A place Pinscape thinks would suit a thought: "wood stain" → B&Q.
struct PlaceSuggestion: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case brand(Brand)
        case category(PlaceCategory)
    }

    var kind: Kind
    /// The words in the note that led here.
    var reason: String

    var target: PlaceTarget {
        switch kind {
        case .brand(let brand): .brand(brand)
        case .category(let category): .category(category)
        }
    }

    var title: String {
        switch kind {
        case .brand(let brand): brand.name
        case .category(let category): category.anyPhrase
        }
    }
}

enum PlaceSuggester {
    /// Ranks places for a note using the item hints in `PlaceCategory`.
    static func suggestions(for note: String, market: Brand.Market = .uk, limit: Int = 4) -> [PlaceSuggestion] {
        let noteKey = " " + TextNormalizer.key(note) + " "
        guard noteKey.count > 2 else { return [] }

        var scored: [(category: PlaceCategory, score: Int, reason: String)] = []
        for category in PlaceCategory.allCases {
            var score = 0
            var reason = ""
            for hint in category.itemHints {
                let hintKey = TextNormalizer.key(hint)
                guard !hintKey.isEmpty else { continue }
                if noteKey.contains(" \(hintKey) ") || noteKey.contains(" \(hintKey)s ") || noteKey.contains(" \(hintKey)es ") {
                    let weight = hintKey.split(separator: " ").count * 2
                    score += weight
                    if reason.isEmpty || hint.count > reason.count { reason = hint }
                }
            }
            if score > 0 {
                scored.append((category, score, reason))
            }
        }
        scored.sort { $0.score == $1.score ? $0.category.rawValue < $1.category.rawValue : $0.score > $1.score }

        var suggestions: [PlaceSuggestion] = []
        for entry in scored {
            let brands = BrandCatalog.all.filter { $0.category == entry.category && $0.market == market }.prefix(2)
            for brand in brands {
                suggestions.append(PlaceSuggestion(kind: .brand(brand), reason: entry.reason))
            }
            if entry.category.isSearchable {
                suggestions.append(PlaceSuggestion(kind: .category(entry.category), reason: entry.reason))
            }
        }
        return Array(suggestions.prefix(limit))
    }

    /// Brands named anywhere in a block of text, such as words read off a screenshot.
    /// Ordered by how often they appear.
    static func brandsMentioned(in text: String) -> [Brand] {
        let tokens = TextNormalizer.tokens(text)
        var counts: [String: (brand: Brand, count: Int, first: Int)] = [:]
        var index = 0
        while index < tokens.count {
            var matched = false
            for length in stride(from: min(BrandCatalog.maxKeyLength, tokens.count - index), through: 1, by: -1) {
                let key = TextNormalizer.key(tokens[index..<(index + length)])
                guard let brand = BrandCatalog.index[key] ?? (key.hasSuffix("s") && key.count > 3 ? BrandCatalog.index[String(key.dropLast())] : nil) else { continue }
                if brand.isCommonWord, !tokens[index].startsWithCapital { continue }
                let existing = counts[brand.name]
                counts[brand.name] = (brand, (existing?.count ?? 0) + 1, existing?.first ?? index)
                index += length
                matched = true
                break
            }
            if !matched { index += 1 }
        }
        return counts.values.sorted { $0.count == $1.count ? $0.first < $1.first : $0.count > $1.count }.map(\.brand)
    }
}
