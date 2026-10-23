import Foundation
import SwiftData

enum PinSource: String, Codable, Sendable {
    case app, voice, siri, share, widget, sticker
}

/// A thought left at a place.
@Model
final class Pin {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var completedAt: Date?
    /// Surfaces on every visit ("this bench = call dad") instead of once.
    var isAmbient: Bool = false
    /// `PlaceTarget` as JSON.
    var placeData: Data = Data()
    /// Denormalised for sorting and grouping.
    var placeName: String = ""
    var placeKindRaw: String = PlaceKind.brand.rawValue
    var capturedByVoice: Bool = false
    var lastSurfacedAt: Date?
    var surfaceCount: Int = 0
    var snoozedUntil: Date?
    var sourceRaw: String = PinSource.app.rawValue

    init(text: String, place: PlaceTarget, isAmbient: Bool = false, capturedByVoice: Bool = false, source: PinSource = .app) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.isAmbient = isAmbient
        self.capturedByVoice = capturedByVoice
        self.sourceRaw = source.rawValue
        self.placeData = (try? JSONEncoder().encode(place)) ?? Data()
        self.placeName = place.title
        self.placeKindRaw = place.kind.rawValue
    }

    var place: PlaceTarget {
        get {
            (try? JSONDecoder().decode(PlaceTarget.self, from: placeData)) ?? PlaceTarget(kind: .search, name: placeName, query: placeName)
        }
        set {
            placeData = (try? JSONEncoder().encode(newValue)) ?? Data()
            placeName = newValue.title
            placeKindRaw = newValue.kind.rawValue
        }
    }

    var isCompleted: Bool { completedAt != nil }

    var source: PinSource { PinSource(rawValue: sourceRaw) ?? .app }
}

enum SavedPlaceKind: String, Codable, Sendable {
    /// A spot on the map: home, gym, Mum's.
    case place
    /// Several chains under one name (Pro).
    case group
    /// An NFC sticker (Pro or Sticker Pack).
    case sticker
}

/// One of your own places, a place group, or an NFC sticker.
@Model
final class SavedPlace {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "house.fill"
    var colorHex: String = "#FF9F0A"
    var latitude: Double = 0
    var longitude: Double = 0
    var radius: Double = 150
    var address: String = ""
    var createdAt: Date = Date()
    var kindRaw: String = SavedPlaceKind.place.rawValue
    /// Brand names for a group, "|" separated.
    var membersRaw: String = ""

    init(name: String, symbol: String, colorHex: String, kind: SavedPlaceKind = .place, center: GeoPoint? = nil, radius: Double = PlaceTarget.savedRadius, address: String = "", members: [String] = []) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.latitude = center?.latitude ?? 0
        self.longitude = center?.longitude ?? 0
        self.radius = radius
        self.address = address
        self.membersRaw = members.joined(separator: "|")
        self.createdAt = Date()
    }

    var kind: SavedPlaceKind { SavedPlaceKind(rawValue: kindRaw) ?? .place }

    var center: GeoPoint {
        get { GeoPoint(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }

    var members: [String] {
        get { membersRaw.split(separator: "|").map(String.init) }
        set { membersRaw = newValue.joined(separator: "|") }
    }

    /// The target a pin uses to point at this place.
    func target(near: Bool = false) -> PlaceTarget {
        switch kind {
        case .place:
            .saved(id: id, name: name, center: center, radius: radius, symbol: symbol, colorHex: colorHex, near: near)
        case .group:
            .group(id: id, name: name, members: members, symbol: symbol, colorHex: colorHex)
        case .sticker:
            PlaceTarget(kind: .sticker, name: name, category: .sticker, savedPlaceID: id, stickerID: id.uuidString, symbolOverride: symbol, colorOverride: colorHex)
        }
    }
}
