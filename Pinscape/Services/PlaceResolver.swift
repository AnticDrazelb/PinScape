import CoreLocation
import Foundation
import MapKit

/// A place you can pick in the place picker.
struct PlaceOption: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var target: PlaceTarget

    init(target: PlaceTarget, title: String? = nil, subtitle: String? = nil) {
        self.target = target
        self.title = title ?? target.title
        self.subtitle = subtitle ?? target.summary
        self.id = "\(target.kind.rawValue):\(self.title):\(target.center?.key ?? ""):\(target.savedPlaceID?.uuidString ?? "")"
    }
}

/// Turns what you said ("Tesco", "near gym", "downtown", "Bristol") into somewhere Pinscape can watch.
@MainActor
enum PlaceResolver {
    enum Outcome {
        case resolved(PlaceTarget)
        /// Several sensible readings; let the person choose.
        case choose([PlaceOption])
        /// "Home" or "work" with no saved place of that name yet.
        case needsSavedPlace(PlaceCategory)
        case notFound
    }

    /// Resolutions that need no lookup (a brand, a kind of place, one of your places), available
    /// immediately so the capture screen never shows a stale place while you type.
    static func resolveInstantly(_ phrase: PlacePhrase, savedPlaces: [SavedPlace]) -> Outcome? {
        guard phrase.anchor == nil else { return nil }
        return offlineOutcome(for: phrase, savedPlaces: savedPlaces)
    }

    private static func offlineOutcome(for phrase: PlacePhrase, savedPlaces: [SavedPlace]) -> Outcome? {
        switch phrase.match {
        case .brand(let brand):
            return .resolved(.brand(brand))
        case .category(let category):
            if !category.isSearchable {
                if let saved = savedPlace(named: category.displayName, in: savedPlaces) {
                    return .resolved(saved.target(near: phrase.isNear))
                }
                return .needsSavedPlace(category)
            }
            return .resolved(.category(category))
        case .saved(let name):
            guard let saved = savedPlace(named: name, in: savedPlaces) else { return .notFound }
            return .resolved(saved.target(near: phrase.isNear))
        case .here, .downtown, .freeform:
            return nil
        }
    }

    static func resolve(_ phrase: PlacePhrase, savedPlaces: [SavedPlace]) async -> Outcome {
        if let anchorName = phrase.anchor, let anchor = savedPlace(named: anchorName, in: savedPlaces), let near = await nearest(phrase, around: anchor) {
            return .resolved(near)
        }
        if let outcome = offlineOutcome(for: phrase, savedPlaces: savedPlaces) {
            return outcome
        }

        switch phrase.match {
        case .brand, .category, .saved:
            return .notFound

        case .here:
            guard let location = await LocationEngine.shared.currentLocation(maxAge: 60) else { return .notFound }
            let detail = await streetName(for: location)
            let name = phrase.text == "Here" ? (detail ?? "This spot") : phrase.text
            return .resolved(.spot(name: name, center: GeoPoint(location.coordinate), radius: phrase.isNear ? PlaceTarget.nearRadius : PlaceTarget.spotRadius, detail: detail))

        case .downtown:
            guard let location = await LocationEngine.shared.currentLocation(maxAge: 600) else { return .notFound }
            guard let town = await townName(for: location) else {
                return .resolved(.area(name: "Downtown", center: GeoPoint(location.coordinate)))
            }
            let centre = await PlaceSearch.shared.search(town, near: location.coordinate, radius: 30_000).first { $0.pointOfInterestCategory == nil }
            let point = centre.map { GeoPoint($0.placemark.coordinate) } ?? GeoPoint(location.coordinate)
            return .resolved(.area(name: "Downtown \(town)", center: point, radius: PlaceTarget.downtownRadius, detail: "Central \(town)"))

        case .freeform:
            return await searchFreeform(phrase)
        }
    }

    /// Looks a phrase up in Apple Maps and decides whether it's a town, a chain, or one place.
    static func searchFreeform(_ phrase: PlacePhrase) async -> Outcome {
        let here = await LocationEngine.shared.currentLocation(maxAge: 600)
        let items = await PlaceSearch.shared.search(phrase.spoken, near: here?.coordinate, radius: 20_000)
        guard let first = items.first else {
            return .resolved(.search(phrase.text))
        }

        let phraseKey = TextNormalizer.key(phrase.spoken)
        // A town or city: "Bristol".
        if first.pointOfInterestCategory == nil, let locality = first.placemark.locality ?? first.placemark.name, TextNormalizer.key(locality) == phraseKey {
            return .resolved(.area(name: locality, center: GeoPoint(first.placemark.coordinate), radius: 4_000, detail: first.placemark.administrativeArea))
        }

        // Several results sharing the name: a chain Pinscape doesn't know yet ("Hobbycraft").
        let sameName = items.filter { TextNormalizer.key($0.name ?? "").hasPrefix(phraseKey) }
        if sameName.count >= 2 {
            var options = [PlaceOption(target: .search(phrase.text), title: "Any \(phrase.text)", subtitle: "Whichever one you walk into")]
            options += sameName.prefix(4).map { option(for: $0) }
            return .choose(options)
        }

        if items.count == 1 {
            return .resolved(option(for: first).target)
        }
        return .choose(items.prefix(5).map { option(for: $0) })
    }

    /// "Pub near office": the closest pub to your saved office.
    private static func nearest(_ phrase: PlacePhrase, around anchor: SavedPlace) async -> PlaceTarget? {
        let query: String
        let category: PlaceCategory
        switch phrase.match {
        case .brand(let brand):
            query = brand.searchQuery
            category = brand.category
        case .category(let match):
            query = match.searchQuery
            category = match
        default:
            return nil
        }
        let items = await PlaceSearch.shared.search(query, near: anchor.center.coordinate, radius: 1_500, pointsOfInterestOnly: true)
        let anchorPoint = anchor.center
        func distance(_ item: MKMapItem) -> Double {
            GeoPoint(item.placemark.coordinate).distance(to: anchorPoint)
        }
        guard let closest = items.min(by: { distance($0) < distance($1) }) else { return nil }
        return .spot(name: closest.name ?? phrase.text, center: GeoPoint(closest.placemark.coordinate), radius: PlaceTarget.storeRadius, category: category, detail: "Near \(anchor.name)")
    }

    static func option(for item: MKMapItem) -> PlaceOption {
        let category = category(for: item)
        let target = PlaceTarget.spot(name: item.name ?? "Place", center: GeoPoint(item.placemark.coordinate), radius: PlaceTarget.storeRadius, category: category, detail: PlaceSearch.address(of: item))
        return PlaceOption(target: target, title: item.name ?? "Place", subtitle: PlaceSearch.address(of: item) ?? "This one place")
    }

    static func category(for item: MKMapItem) -> PlaceCategory {
        if let name = item.name, let brand = BrandCatalog.brand(named: name) ?? PlaceSuggester.brandsMentioned(in: name).first {
            return brand.category
        }
        guard let poi = item.pointOfInterestCategory else { return .spot }
        switch poi {
        case .foodMarket: return .supermarket
        case .pharmacy: return .pharmacy
        case .cafe: return .cafe
        case .restaurant: return .restaurant
        case .bakery: return .bakery
        case .nightlife, .brewery, .winery: return .pub
        case .gasStation, .evCharger: return .fuel
        case .fitnessCenter: return .gym
        case .park, .nationalPark, .beach: return .park
        case .library: return .library
        case .postOffice: return .postOffice
        case .bank, .atm: return .bank
        case .publicTransport: return .transit
        case .airport: return .airport
        case .hospital: return .health
        case .school, .university: return .school
        case .store: return .other
        default: return .spot
        }
    }

    static func savedPlace(named name: String, in places: [SavedPlace]) -> SavedPlace? {
        let parser = CaptureParser(savedPlaceNames: places.map(\.name))
        if case .saved(let match)? = parser.classify(name)?.match {
            return places.first { $0.name == match }
        }
        let key = TextNormalizer.key(name)
        return places.first { TextNormalizer.key($0.name) == key }
    }

    private static func placemark(for location: CLLocation) async -> CLPlacemark? {
        try? await CLGeocoder().reverseGeocodeLocation(location).first
    }

    static func streetName(for location: CLLocation) async -> String? {
        guard let placemark = await placemark(for: location) else { return nil }
        return placemark.areasOfInterest?.first ?? placemark.thoroughfare ?? placemark.subLocality
    }

    static func townName(for location: CLLocation) async -> String? {
        await placemark(for: location)?.locality
    }
}
