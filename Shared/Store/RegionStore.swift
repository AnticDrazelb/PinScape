import Foundation

/// The regions Core Location is watching, saved so an arrival that relaunches
/// Pinscape in the background can be matched to its pins straight away.
enum RegionStore {
    static func load() -> [PlannedRegion] {
        guard let data = AppGroup.defaults.data(forKey: SharedKeys.plannedRegions) else { return [] }
        return (try? JSONDecoder().decode([PlannedRegion].self, from: data)) ?? []
    }

    static func save(_ regions: [PlannedRegion]) {
        AppGroup.defaults.set(try? JSONEncoder().encode(regions), forKey: SharedKeys.plannedRegions)
    }
}

/// A place you're at right now, with the pins that surfaced there.
struct Visit: Codable, Hashable, Identifiable {
    var regionID: String
    var placeKey: String
    var title: String
    var subtitle: String?
    var symbol: String
    var colorHex: String
    var arrivedAt: Date
    var pinIDs: [UUID]

    var id: String { regionID }
}

enum VisitStore {
    /// Visits older than this are assumed over, in case the exit event was missed.
    static let maximumLength: TimeInterval = 3 * 60 * 60

    static func current() -> [Visit] {
        guard let data = AppGroup.defaults.data(forKey: SharedKeys.currentVisits),
              let visits = try? JSONDecoder().decode([Visit].self, from: data) else { return [] }
        return visits.filter { Date().timeIntervalSince($0.arrivedAt) < maximumLength }
    }

    static func begin(_ visit: Visit) {
        var visits = current().filter { $0.regionID != visit.regionID }
        visits.append(visit)
        store(visits)
    }

    static func end(regionID: String) {
        store(current().filter { $0.regionID != regionID })
    }

    private static func store(_ visits: [Visit]) {
        AppGroup.defaults.set(try? JSONEncoder().encode(visits), forKey: SharedKeys.currentVisits)
    }
}
