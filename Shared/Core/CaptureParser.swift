import Foundation

/// What a place phrase turned out to be.
enum PlaceMatch: Equatable, Sendable {
    case brand(Brand)
    case category(PlaceCategory)
    /// One of your saved places, by its saved name.
    case saved(String)
    /// Where you're standing: "here", "this bench".
    case here
    /// The centre of the town you're in.
    case downtown
    /// Something to look up in Apple Maps: "Bristol", "Hobbycraft".
    case freeform
}

struct PlacePhrase: Equatable, Sendable {
    /// Display text: "B&Q", "Pharmacy", "This bench", "Bristol".
    var text: String
    /// What was actually said, for searching.
    var spoken: String
    var match: PlaceMatch
    /// "near gym" rather than "at gym".
    var isNear: Bool
    /// The landmark in "pub near office": find the place closest to this.
    var anchor: String? = nil
}

struct ParsedCapture: Equatable, Sendable {
    var note: String
    var place: PlacePhrase?
    /// Surface on every visit rather than once.
    var isAmbient: Bool
}

/// Splits a spoken or typed capture into a thought and a place.
///
///     "Tesco, batteries"                     → Tesco · "Batteries"
///     "wood stain the dark one at B&Q"       → B&Q · "Wood stain the dark one"
///     "this bench = call dad"                → This bench · "Call dad" (every visit)
///     "near gym, book a PT session"          → near Gym · "Book a PT session"
///     "when I'm in Bristol try Sarah's café" → Bristol · "Try Sarah's café"
struct CaptureParser {
    var savedPlaceNames: [String]

    init(savedPlaceNames: [String] = []) {
        self.savedPlaceNames = savedPlaceNames
    }

    func parse(_ raw: String) -> ParsedCapture {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ambient = Self.hasAmbientCue(trimmed)
        let text = Self.dropLeading(Self.capturePrefixes, from: trimmed)
        guard !text.isEmpty else {
            return ParsedCapture(note: "", place: nil, isAmbient: false)
        }

        func result(_ note: String, _ place: PlacePhrase?) -> ParsedCapture {
            ParsedCapture(note: Self.cleanNote(note), place: place, isAmbient: ambient)
        }

        // "this bench = call dad"
        if let equals = text.firstIndex(of: "=") {
            let left = String(text[..<equals])
            let right = String(text[text.index(after: equals)...])
            if !Self.cleanNote(right).isEmpty, let place = classify(left) ?? freeform(TextNormalizer.tokens(left), requireCapital: false) {
                return ParsedCapture(note: Self.cleanNote(right), place: place, isAmbient: true)
            }
        }

        // "Tesco, batteries" / "B&Q: wood stain" / "batteries – Tesco"
        if let (left, right) = Self.splitAtFirstDelimiter(text) {
            if let place = classify(left) {
                return result(right, place)
            }
            if TextNormalizer.tokens(right).count <= 4, let place = classify(right) {
                return result(left, place)
            }
            let leftTokens = TextNormalizer.tokens(left)
            if let trigger = Self.leadingTrigger(in: leftTokens) {
                let phrase = Array(leftTokens.dropFirst(trigger.length))
                if let place = classify(phrase, near: trigger.near) ?? freeform(phrase, requireCapital: true, near: trigger.near) {
                    return result(right, place)
                }
            }
            if let place = properNounPlace(leftTokens, followedBy: right) {
                return result(right, place)
            }
        }

        let tokens = TextNormalizer.tokens(text)

        // "at B&Q wood stain the dark one" / "when I get to Tesco buy milk"
        if let trigger = Self.leadingTrigger(in: tokens) {
            let rest = Array(tokens.dropFirst(trigger.length))
            if let (place, length) = knownPrefix(of: rest, near: trigger.near) {
                return result(Self.join(rest.dropFirst(length)), place)
            }
            let run = Array(rest.prefix { $0.startsWithCapital }.prefix(3))
            if !run.isEmpty, run.count < rest.count, let place = freeform(run, requireCapital: true, near: trigger.near) {
                return result(Self.join(rest.dropFirst(run.count)), place)
            }
        }

        // "buy batteries at Tesco" / "call dad when I'm at this bench"
        for split in Self.trailingTriggers(in: tokens) {
            if let place = classify(split.phrase, near: split.near) ?? freeform(split.phrase, requireCapital: true, near: split.near) {
                return result(Self.join(split.note), place)
            }
        }

        // "batteries Tesco" / "creative ideas happen here"
        if let (place, note) = scanForKnownPlace(tokens) {
            return result(Self.join(note), place)
        }

        return result(text, nil)
    }

    // MARK: - Classifying a phrase

    /// Recognises a phrase that names a known place. Returns nil for anything that would need a map search.
    func classify(_ phrase: String) -> PlacePhrase? {
        classify(TextNormalizer.tokens(phrase))
    }

    func classify(_ tokens: [Token], near nearAlready: Bool = false, strict: Bool = false) -> PlacePhrase? {
        var words = tokens[...]
        var near = nearAlready

        while let first = words.first {
            if Self.nearWords.contains(first.norm) {
                near = true
                words = words.dropFirst()
            } else if first.norm == "close", words.dropFirst().first?.norm == "to" {
                near = true
                words = words.dropFirst(2)
            } else if Self.placePrepositions.contains(first.norm) {
                words = words.dropFirst()
            } else {
                break
            }
        }
        while let first = words.first, first.norm != "this", TextNormalizer.articles.contains(first.norm) {
            words = words.dropFirst()
        }
        guard !words.isEmpty else { return nil }

        let spoken = Self.join(words)
        let key = TextNormalizer.key(words)

        if Self.hereKeys.contains(key) {
            return PlacePhrase(text: "Here", spoken: spoken, match: .here, isNear: near)
        }
        if words.count == 2, words.first?.norm == "this", let noun = words.last, !Self.notPlaceNouns.contains(noun.norm) {
            return PlacePhrase(text: TextNormalizer.sentenceCase(spoken.lowercased()), spoken: spoken, match: .here, isNear: near)
        }
        if words.first?.norm == "this" {
            words = words.dropFirst()
            guard !words.isEmpty else { return nil }
        }
        let bareKey = TextNormalizer.key(words)

        if let saved = savedPlace(matching: bareKey) {
            return PlacePhrase(text: saved, spoken: spoken, match: .saved(saved), isNear: near)
        }
        if let brand = Self.brand(matching: Array(words), strict: strict) {
            return PlacePhrase(text: brand.name, spoken: spoken, match: .brand(brand), isNear: near)
        }
        if let category = Self.category(matching: bareKey) {
            return PlacePhrase(text: category.displayName, spoken: spoken, match: .category(category), isNear: near)
        }
        if Self.downtownKeys.contains(bareKey) {
            return PlacePhrase(text: "Downtown", spoken: spoken, match: .downtown, isNear: near)
        }
        // "pub near office": the place is the pub, the office is where to look for it.
        if !strict, let split = words.firstIndex(where: { Self.nearWords.contains($0.norm) }), split > words.startIndex, split < words.endIndex - 1 {
            let anchor = Self.join(words[(split + 1)...])
            if var place = classify(Array(words[..<split]), near: near, strict: true) {
                place.anchor = anchor
                return place
            }
        }
        return nil
    }

    private func savedPlace(matching key: String) -> String? {
        for name in savedPlaceNames {
            let nameKey = TextNormalizer.key(name)
            let words = nameKey.split(separator: " ").map(String.init)
            var options: Set<String> = [nameKey]
            if let first = words.first, ["my", "the", "our"].contains(first) {
                options.insert(words.dropFirst().joined(separator: " "))
            }
            // "Mum's" for "Mum's house"
            if words.count == 2, ["house", "place", "flat", "home"].contains(words[1]) {
                options.insert(words[0])
            }
            if options.contains(key) {
                return name
            }
        }
        return nil
    }

    private static func brand(matching words: [Token], strict: Bool) -> Brand? {
        let key = TextNormalizer.key(words)
        if let brand = BrandCatalog.index[key] { return brand }
        if key.hasSuffix("s"), let brand = BrandCatalog.index[String(key.dropLast())] { return brand }
        guard !strict, words.count > 1 else { return nil }
        // "Tesco Camden", "IKEA Wembley": a brand followed by a couple of words is still that brand.
        for length in stride(from: min(words.count - 1, BrandCatalog.maxKeyLength), through: 1, by: -1) where words.count - length <= 2 {
            let prefixKey = TextNormalizer.key(words.prefix(length))
            if let brand = BrandCatalog.index[prefixKey] { return brand }
        }
        return nil
    }

    private static func category(matching key: String) -> PlaceCategory? {
        if let category = categoryIndex[key] { return category }
        if key.hasSuffix("s"), let category = categoryIndex[String(key.dropLast())] { return category }
        return nil
    }

    private func freeform(_ tokens: [Token], requireCapital: Bool, near: Bool = false) -> PlacePhrase? {
        var words = tokens[...]
        var near = near
        while let first = words.first, Self.nearWords.contains(first.norm) || Self.placePrepositions.contains(first.norm) || TextNormalizer.articles.contains(first.norm) {
            if Self.nearWords.contains(first.norm) { near = true }
            words = words.dropFirst()
        }
        guard (1...4).contains(words.count) else { return nil }
        if requireCapital {
            guard words.first?.startsWithCapital == true else { return nil }
        }
        let spoken = Self.join(words)
        return PlacePhrase(text: TextNormalizer.titleCase(spoken), spoken: spoken, match: .freeform, isNear: near)
    }

    /// "Bristol, try that bakery" — a short capitalised name before a comma is probably a place,
    /// unless it reads like the start of a list ("Milk, eggs, bread") or a person ("Dad, …").
    private func properNounPlace(_ tokens: [Token], followedBy rest: String) -> PlacePhrase? {
        guard (1...3).contains(tokens.count), tokens.first?.startsWithCapital == true else { return nil }
        guard !rest.contains(","), !Self.peopleWords.contains(tokens[0].norm) else { return nil }
        let key = TextNormalizer.key(tokens)
        let isItem = PlaceCategory.allCases.contains { category in
            category.itemHints.contains { TextNormalizer.key($0) == key }
        }
        guard !isItem else { return nil }
        return freeform(tokens, requireCapital: true)
    }

    private func knownPrefix(of tokens: [Token], near: Bool) -> (PlacePhrase, Int)? {
        let longest = min(tokens.count, BrandCatalog.maxKeyLength + 2)
        guard longest > 0 else { return nil }
        for length in stride(from: longest, through: 1, by: -1) {
            if let place = classify(Array(tokens.prefix(length)), near: near, strict: true) {
                return (place, length)
            }
        }
        return nil
    }

    private func scanForKnownPlace(_ tokens: [Token]) -> (PlacePhrase, [Token])? {
        var best: (score: Int, start: Int, length: Int, place: PlacePhrase, preposition: Bool)?
        for start in tokens.indices {
            let longest = min(BrandCatalog.maxKeyLength + 2, tokens.count - start)
            for length in stride(from: longest, through: 1, by: -1) {
                let slice = Array(tokens[start..<(start + length)])
                guard let place = classify(slice, strict: true) else { continue }
                let previous = start > 0 ? tokens[start - 1].norm : nil
                let hasPreposition = previous.map { Self.placePrepositions.contains($0) || Self.nearWords.contains($0) || TextNormalizer.articles.contains($0) } ?? false
                var score: Int
                switch place.match {
                case .brand(let brand):
                    if brand.isCommonWord, !hasPreposition, !(start > 0 && slice[0].startsWithCapital) { continue }
                    score = 3
                case .saved:
                    guard hasPreposition || start == 0 else { continue }
                    score = 4
                case .category:
                    guard hasPreposition else { continue }
                    score = 2
                case .downtown:
                    guard hasPreposition else { continue }
                    score = 1
                case .here:
                    score = 1
                case .freeform:
                    continue
                }
                if hasPreposition { score += 1 }
                if best == nil || score >= best!.score {
                    best = (score, start, length, place, hasPreposition)
                }
                break
            }
        }
        guard let best else { return nil }

        if best.place.match == .here, !best.preposition {
            // "creative ideas happen here" reads fine as it is.
            return (best.place, tokens)
        }
        // Take the "when I'm at the" in front of the place with it.
        var removeFrom = best.start
        while removeFrom > 0 {
            if let trigger = Self.trigger(endingAt: removeFrom - 1, in: tokens) {
                removeFrom -= trigger.length
            } else if Self.connectingWords.contains(tokens[removeFrom - 1].norm) {
                removeFrom -= 1
            } else {
                break
            }
        }
        var note = Array(tokens[..<removeFrom])
        note.append(contentsOf: tokens[(best.start + best.length)...])
        return (best.place, note)
    }

    // MARK: - Triggers

    struct Trigger {
        var words: [String]
        var near: Bool
    }

    static let triggers: [Trigger] = {
        var list: [Trigger] = []
        let leads: [[String]] = [
            ["when", "im"], ["when", "i", "am"], ["whenever", "im"], ["next", "time", "im"], ["once", "im"], ["every", "time", "im"], ["if", "im"],
        ]
        for lead in leads {
            list.append(Trigger(words: lead + ["at"], near: false))
            list.append(Trigger(words: lead + ["in"], near: false))
            list.append(Trigger(words: lead + ["near"], near: true))
            list.append(Trigger(words: lead + ["by"], near: true))
            list.append(Trigger(words: lead + ["passing"], near: true))
        }
        let others: [[String]] = [
            ["when", "i", "get", "to"], ["when", "i", "arrive", "at"], ["when", "i", "reach"], ["when", "i", "go", "to"],
            ["when", "i", "visit"], ["next", "time", "i", "go", "to"], ["next", "time", "at"], ["next", "time", "in"],
            ["at"], ["in"], ["inside"],
        ]
        list += others.map { Trigger(words: $0, near: false) }
        list += [["when", "i", "pass"], ["near"], ["around"], ["outside"]].map { Trigger(words: $0, near: true) }
        return list.sorted { $0.words.count > $1.words.count }
    }()

    static func leadingTrigger(in tokens: [Token]) -> (length: Int, near: Bool)? {
        for trigger in triggers where tokens.count > trigger.words.count {
            if tokens.prefix(trigger.words.count).map(\.norm) == trigger.words {
                return (trigger.words.count, trigger.near)
            }
        }
        return nil
    }

    /// The trigger whose last word sits at `index`, longest first.
    static func trigger(endingAt index: Int, in tokens: [Token]) -> (length: Int, near: Bool)? {
        guard index >= 0, index < tokens.count else { return nil }
        for trigger in triggers {
            let start = index - trigger.words.count + 1
            guard start >= 0 else { continue }
            if tokens[start...index].map(\.norm) == trigger.words {
                return (trigger.words.count, trigger.near)
            }
        }
        return nil
    }

    /// Every way of reading the capture as "<thought> <trigger> <place>", latest trigger first.
    static func trailingTriggers(in tokens: [Token]) -> [(note: [Token], phrase: [Token], near: Bool)] {
        var splits: [(note: [Token], phrase: [Token], near: Bool)] = []
        guard tokens.count >= 3 else { return splits }
        for end in stride(from: tokens.count - 2, through: 1, by: -1) {
            guard let trigger = trigger(endingAt: end, in: tokens) else { continue }
            let start = end - trigger.length + 1
            let phrase = Array(tokens[(end + 1)...])
            guard start >= 1, (1...5).contains(phrase.count) else { continue }
            splits.append((Array(tokens[..<start]), phrase, trigger.near))
        }
        return splits
    }

    // MARK: - Text helpers

    static func splitAtFirstDelimiter(_ text: String) -> (String, String)? {
        var best: Range<String.Index>?
        for delimiter in [",", ":", ";", " - ", " – ", " — ", "—", "–"] {
            if let range = text.range(of: delimiter), best == nil || range.lowerBound < best!.lowerBound {
                best = range
            }
        }
        guard let best else { return nil }
        let left = text[..<best.lowerBound].trimmingCharacters(in: .whitespaces)
        let right = text[best.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return (left, right)
    }

    static func join(_ tokens: some Sequence<Token>) -> String {
        tokens.map(\.original).joined(separator: " ").trimmingCharacters(in: trimSet)
    }

    private static let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:-–—=…"))

    static func cleanNote(_ text: String) -> String {
        var note = text.trimmingCharacters(in: trimSet)
        note = dropLeading(notePrefixes, from: note)
        var tokens = TextNormalizer.tokens(note)
        while tokens.last?.norm == "please" {
            tokens.removeLast()
        }
        // Speech recognition often hears "Buy paracetamol" as "By paracetamol". A note that starts
        // with "by" and then names a thing, rather than a time or place, is a shopping item.
        if tokens.count > 1, tokens[0].norm == "by", !notBuyFollowers.contains(tokens[1].norm), Int(tokens[1].norm) == nil {
            tokens[0] = Token(original: "Buy", norm: "buy", endsClause: tokens[0].endsClause)
        }
        note = join(tokens)
        return TextNormalizer.sentenceCase(note)
    }

    /// Words after a leading "by" that mean "by" really was meant: "By Friday", "By the door".
    private static let notBuyFollowers: Set<String> = [
        "the", "my", "your", "his", "her", "their", "our", "this", "that", "next", "end", "then", "now",
        "today", "tonight", "tomorrow", "noon", "midnight", "morning", "evening", "lunchtime", "bedtime",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "weekend",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
    ]

    static func dropLeading(_ prefixes: [[String]], from text: String) -> String {
        let tokens = TextNormalizer.tokens(text)
        var skip = 0
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes where tokens.count - skip > prefix.count {
                if tokens[skip..<(skip + prefix.count)].map(\.norm) == prefix {
                    skip += prefix.count
                    changed = true
                    break
                }
            }
        }
        guard skip > 0 else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Cut the original text rather than rebuilding it, so punctuation like "=" survives.
        return String(text[indexAfterSkipping(words: skip, in: text)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where `text` continues after its first `count` words. Punctuation-only chunks aren't words.
    private static func indexAfterSkipping(words count: Int, in text: String) -> String.Index {
        var skipped = 0
        var index = text.startIndex
        while index < text.endIndex, skipped < count {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            let wordStart = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
            if !TextNormalizer.normalize(text[wordStart..<index]).isEmpty {
                skipped += 1
            }
        }
        return index
    }

    static func hasAmbientCue(_ text: String) -> Bool {
        let key = " " + TextNormalizer.key(text) + " "
        return text.contains("=") || ambientCues.contains { key.contains(" \($0) ") }
    }

    // MARK: - Vocabulary

    static let capturePrefixes: [[String]] = [
        ["hey", "pinscape"], ["pinscape"], ["drop", "a", "pin"], ["new", "pin"], ["note", "to", "self"],
        ["remind", "me", "to"], ["remind", "me"], ["remember", "to"], ["dont", "forget", "to"], ["dont", "forget"],
    ]

    static let notePrefixes: [[String]] = [
        ["remind", "me", "to"], ["remember", "to"], ["dont", "forget", "to"], ["note", "to", "self"],
        ["to"], ["and"], ["then"], ["please"],
    ]

    static let ambientCues = ["every time", "everytime", "whenever", "each time", "always", "every visit"]

    static let nearWords: Set<String> = ["near", "nearby", "around", "by", "outside", "passing"]

    static let placePrepositions: Set<String> = ["at", "in", "to", "inside", "from", "into"]

    /// Words between a thought and its place that belong to neither: "to the", "at any".
    static let connectingWords: Set<String> = placePrepositions.union(nearWords).union(["the", "a", "an", "any", "my", "our", "some"])

    static let hereKeys: Set<String> = ["here", "right here", "where i am", "my location", "current location", "my current location", "here now"]

    static let downtownKeys: Set<String> = ["downtown", "city centre", "city center", "town centre", "town center", "town", "city", "high street", "centre", "center", "midtown"]

    /// "this morning", "this week" and friends are times, not places.
    static let notPlaceNouns: Set<String> = ["morning", "afternoon", "evening", "week", "weekend", "month", "year", "time", "one", "thing", "is", "was", "and", "for", "to", "in", "at"]

    static let peopleWords: Set<String> = ["mum", "mom", "dad", "mother", "father", "sister", "brother", "wife", "husband", "partner", "son", "daughter", "nan", "nana", "grandma", "grandad", "granddad", "grandpa", "boss", "me", "i"]

    static let categoryIndex: [String: PlaceCategory] = {
        var index: [String: PlaceCategory] = [:]
        for category in PlaceCategory.allCases {
            for word in category.placeWords {
                let key = TextNormalizer.key(word)
                if index[key] == nil { index[key] = category }
            }
        }
        return index
    }()
}
