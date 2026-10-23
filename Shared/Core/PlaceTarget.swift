import Foundation

struct GeoPoint: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres.
    func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// "51.50740,-0.12780", stable enough to identify a place.
    var key: String {
        String(format: "%.5f,%.5f", latitude, longitude)
    }
}

enum PlaceKind: String, Codable, CaseIterable, Sendable {
    /// Any branch of a chain: "Tesco".
    case brand
    /// Any place of a kind: "a pharmacy".
    case category
    /// Anything Apple Maps finds for a phrase, wherever you are: "Hobbycraft".
    case search
    /// One location: a shop, an address, the bench you're sitting on.
    case spot
    /// A neighbourhood or city: "Downtown", "Bristol".
    case area
    /// One of your own places: "Mum's house", "near gym".
    case saved
    /// A group of chains you defined: "Supermarkets" = Tesco + Aldi + Lidl.
    case group
    /// An NFC sticker on your pantry door.
    case sticker
}

/// Where a pin lives. Stored with the pin as JSON so new kinds never need a migration.
struct PlaceTarget: Codable, Hashable, Sendable {
    var kind: PlaceKind
    var name: String
    var query: String?
    var category: PlaceCategory?
    var center: GeoPoint?
    var radius: Double
    var savedPlaceID: UUID?
    var members: [String]?
    var stickerID: String?
    var detail: String?
    var symbolOverride: String?
    var colorOverride: String?

    init(kind: PlaceKind, name: String, query: String? = nil, category: PlaceCategory? = nil, center: GeoPoint? = nil, radius: Double = PlaceTarget.storeRadius, savedPlaceID: UUID? = nil, members: [String]? = nil, stickerID: String? = nil, detail: String? = nil, symbolOverride: String? = nil, colorOverride: String? = nil) {
        self.kind = kind
        self.name = name
        self.query = query
        self.category = category
        self.center = center
        self.radius = radius
        self.savedPlaceID = savedPlaceID
        self.members = members
        self.stickerID = stickerID
        self.detail = detail
        self.symbolOverride = symbolOverride
        self.colorOverride = colorOverride
    }

    // MARK: Radii

    /// A shop and its car park.
    static let storeRadius: Double = 150
    /// "This bench".
    static let spotRadius: Double = 100
    /// One of your places.
    static let savedRadius: Double = 150
    /// "Near gym".
    static let nearRadius: Double = 400
    /// "Downtown".
    static let downtownRadius: Double = 1_000

    // MARK: Factories

    static func brand(_ brand: Brand) -> PlaceTarget {
        PlaceTarget(kind: .brand, name: brand.name, query: brand.searchQuery, category: brand.category)
    }

    static func category(_ category: PlaceCategory) -> PlaceTarget {
        PlaceTarget(kind: .category, name: category.displayName, query: category.searchQuery, category: category)
    }

    static func search(_ phrase: String) -> PlaceTarget {
        PlaceTarget(kind: .search, name: phrase, query: phrase, category: .other)
    }

    static func spot(name: String, center: GeoPoint, radius: Double = PlaceTarget.spotRadius, category: PlaceCategory = .spot, detail: String? = nil) -> PlaceTarget {
        PlaceTarget(kind: .spot, name: name, category: category, center: center, radius: radius, detail: detail)
    }

    static func area(name: String, center: GeoPoint, radius: Double = PlaceTarget.downtownRadius, detail: String? = nil) -> PlaceTarget {
        PlaceTarget(kind: .area, name: name, category: .area, center: center, radius: radius, detail: detail)
    }

    static func saved(id: UUID, name: String, center: GeoPoint, radius: Double, symbol: String, colorHex: String, near: Bool = false) -> PlaceTarget {
        PlaceTarget(kind: .saved, name: name, category: .other, center: center, radius: near ? max(radius, nearRadius) : radius, savedPlaceID: id, detail: near ? "near" : nil, symbolOverride: symbol, colorOverride: colorHex)
    }

    static func group(id: UUID, name: String, members: [String], symbol: String, colorHex: String) -> PlaceTarget {
        PlaceTarget(kind: .group, name: name, category: .other, savedPlaceID: id, members: members, symbolOverride: symbol, colorOverride: colorHex)
    }

    static func sticker(id: String, name: String) -> PlaceTarget {
        PlaceTarget(kind: .sticker, name: name, category: .sticker, stickerID: id)
    }

    // MARK: Presentation

    var isNear: Bool { kind == .saved && detail == "near" }

    var symbol: String {
        symbolOverride ?? (category ?? .other).symbol
    }

    var colorHex: String {
        colorOverride ?? (category ?? .other).colorHex
    }

    /// The short title used on chips and notifications: "Tesco", "Near Gym".
    var title: String {
        isNear ? "Near \(name)" : name
    }

    /// How Pinscape will find the place, in plain words.
    var summary: String {
        switch kind {
        case .brand: "Any \(name) you walk into"
        case .category: "\((category ?? .other).anyPhrase) nearby"
        case .search: "Anywhere matching “\(name)”"
        case .spot: detail ?? "Within \(Self.formatDistance(radius)) of this spot"
        case .area: "Anywhere within \(Self.formatDistance(radius)) of \(name)"
        case .saved: "Within \(Self.formatDistance(radius)) of \(name)"
        case .group: "Any of " + (members ?? []).joined(separator: ", ")
        case .sticker: "When you tap the \(name) sticker"
        }
    }

    static func formatDistance(_ metres: Double) -> String {
        if metres < 1_000 {
            return "\(Int((metres / 10).rounded() * 10)) m"
        }
        let km = metres / 1_000
        return km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
    }

    // MARK: Geofencing

    /// Kinds whose locations are looked up near you and refreshed as you move.
    var isDynamic: Bool {
        switch kind {
        case .brand, .category, .search, .group: true
        case .spot, .area, .saved, .sticker: false
        }
    }

    /// The searches to run for a dynamic place, keyed by the region key they produce.
    var searches: [PlaceSearchSpec] {
        switch kind {
        case .brand:
            return [PlaceSearchSpec(key: Self.brandKey(name), query: query ?? name, brandName: name, category: category)]
        case .category:
            let category = category ?? .other
            return [PlaceSearchSpec(key: "category:\(category.rawValue)", query: category.searchQuery, brandName: nil, category: category)]
        case .search:
            let phrase = query ?? name
            return [PlaceSearchSpec(key: "search:\(TextNormalizer.key(phrase))", query: phrase, brandName: nil, category: nil)]
        case .group:
            return (members ?? []).map { member in
                let brand = BrandCatalog.brand(named: member)
                return PlaceSearchSpec(key: Self.brandKey(brand?.name ?? member), query: brand?.searchQuery ?? member, brandName: brand?.name ?? member, category: brand?.category)
            }
        case .spot, .area, .saved, .sticker:
            return []
        }
    }

    /// The single region key for a fixed place.
    var fixedKey: String? {
        switch kind {
        case .saved:
            guard let savedPlaceID else { return nil }
            return "saved:\(savedPlaceID.uuidString):\(Int(radius))"
        case .spot, .area:
            guard let center else { return nil }
            return "spot:\(center.key):\(Int(radius))"
        default:
            return nil
        }
    }

    /// Whether arriving in the region with this key should surface the pin.
    func matches(regionKey: String) -> Bool {
        if let fixedKey { return fixedKey == regionKey }
        return searches.contains { $0.key == regionKey }
    }

    static func brandKey(_ name: String) -> String {
        "brand:\(TextNormalizer.key(name))"
    }
}

/// One Apple Maps search that finds branches of a dynamic place near you.
struct PlaceSearchSpec: Hashable, Sendable {
    var key: String
    var query: String
    /// When set, results must carry this brand in their name, so "Tesco" never matches "Tesco Bank ATM's neighbour".
    var brandName: String?
    var category: PlaceCategory?

    /// Whether a place Apple Maps returned really belongs to this search.
    func accepts(resultName: String) -> Bool {
        guard let brandName else { return true }
        let resultKey = " " + TextNormalizer.key(resultName) + " "
        let brand = BrandCatalog.brand(named: brandName)
        let spellings = brand.map { b in ([b.name] + b.aliases).flatMap(TextNormalizer.keyVariants(of:)) } ?? TextNormalizer.keyVariants(of: brandName)
        let squashedResult = resultKey.replacingOccurrences(of: " ", with: "")
        return spellings.contains { spelling in
            if resultKey.contains(" " + spelling + " ") { return true }
            // "WH Smith" vs "WHSmith": compare without spaces, but only for names long enough not to collide.
            let squashed = spelling.replacingOccurrences(of: " ", with: "")
            return squashed.count >= 5 && squashedResult.contains(squashed)
        }
    }
}
