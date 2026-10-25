import Foundation

/// A place that could be watched: one Tesco, your gym, downtown.
struct RegionCandidate: Hashable, Codable, Sendable {
    /// Which pins this region serves. See `PlaceTarget.matches(regionKey:)`.
    var key: String
    /// "Tesco Express"
    var title: String
    /// "12 Camden High St"
    var subtitle: String?
    var center: GeoPoint
    var radius: Double
    var symbol: String
    var colorHex: String
}

/// A region handed to Core Location.
struct PlannedRegion: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var candidate: RegionCandidate
    /// You were already inside when it was planned, so arriving now shouldn't count.
    var startsInside: Bool
}

struct GeofencePlan: Sendable {
    var regions: [PlannedRegion]
    /// A circle around you; leaving it means it's time to plan again.
    var boundary: PlannedRegion?

    var all: [PlannedRegion] {
        regions + (boundary.map { [$0] } ?? [])
    }
}

/// iOS watches at most 20 regions per app, but "any Tesco" can mean hundreds of shops.
/// The planner watches only what you could reach before the next re-plan, and draws a boundary
/// around you; crossing it wakes Pinscape to swap in what's nearest then.
enum GeofencePlanner {
    static let regionLimit = 20
    static let minimumRadius = 100.0
    static let maximumRadius = 25_000.0
    static let boundaryID = "pinscape.boundary"
    /// Bumped when the planning rules change, so an existing plan is redone with the new ones.
    static let rulesVersion = 2
    /// Branches of one chain or kind of place watched at once, at most.
    static let branchesPerPlace = 5
    /// How far past the boundary a branch is still worth watching: leaving the boundary takes iOS
    /// a moment to notice and the re-plan a moment to search, and you keep moving meanwhile.
    static let reachMargin = 1_500.0

    /// - Parameters:
    ///   - candidates: every place a pin could surface at, in priority order.
    ///   - user: where you are now, if known.
    ///   - refreshDistance: how far you can travel before dynamic places (brands, categories) need searching again.
    ///
    /// The nearest branch of every place is always watched, however far away, so every pin is
    /// armed. Further branches are watched only within reach before the next re-plan
    /// (`refreshDistance` plus `reachMargin`), at most `branchesPerPlace` each. Anything left out
    /// is outside the boundary, so you can't walk into a place that isn't watched without
    /// Pinscape re-planning first.
    static func plan(candidates: [RegionCandidate], around user: GeoPoint?, limit: Int = regionLimit, refreshDistance: Double? = nil, branchesPerPlace: Int = branchesPerPlace) -> GeofencePlan {
        let unique = deduplicate(candidates.map(clamped))

        guard let user else {
            let regions = unique.prefix(limit).map { PlannedRegion(id: regionID(for: $0), candidate: $0, startsInside: false) }
            return GeofencePlan(regions: Array(regions), boundary: nil)
        }

        let ranked: [(candidate: RegionCandidate, distance: Double)] = unique
            .map { candidate in (candidate: candidate, distance: edgeDistance(from: user, to: candidate)) }
            .sorted { (lhs: (candidate: RegionCandidate, distance: Double), rhs: (candidate: RegionCandidate, distance: Double)) -> Bool in
                if lhs.distance == rhs.distance { return lhs.candidate.key < rhs.candidate.key }
                return lhs.distance < rhs.distance
            }
        let reach = refreshDistance.map { $0 + reachMargin }

        func select(capacity: Int) -> (chosen: [(candidate: RegionCandidate, distance: Double)], firstLeftOut: Double?) {
            var chosen: [(candidate: RegionCandidate, distance: Double)] = []
            var firstLeftOut: Double?
            var perPlace: [String: Int] = [:]
            for entry in ranked {
                let count = perPlace[entry.candidate.key, default: 0]
                let worthWatching = count == 0 || (count < branchesPerPlace && reach.map { entry.distance <= $0 } ?? true)
                if worthWatching, chosen.count < capacity {
                    chosen.append(entry)
                    perPlace[entry.candidate.key] = count + 1
                } else if firstLeftOut == nil {
                    firstLeftOut = entry.distance
                }
            }
            return (chosen, firstLeftOut)
        }

        // A boundary takes one of the 20 slots. It's needed to refresh dynamic places, or when
        // anything had to be left out.
        var selection = select(capacity: refreshDistance == nil ? limit : limit - 1)
        let needsBoundary = refreshDistance != nil || selection.firstLeftOut != nil
        if needsBoundary, refreshDistance == nil {
            selection = select(capacity: limit - 1)
        }

        let regions: [PlannedRegion] = selection.chosen.map { entry in
            let inside = user.distance(to: entry.candidate.center) <= entry.candidate.radius
            return PlannedRegion(id: regionID(for: entry.candidate), candidate: entry.candidate, startsInside: inside)
        }

        var boundary: PlannedRegion?
        if needsBoundary {
            var radius = refreshDistance ?? maximumRadius
            if let firstLeftOut = selection.firstLeftOut {
                // Re-plan before reaching the nearest place that isn't watched.
                radius = min(radius, firstLeftOut)
            }
            radius = min(max(radius, 250), maximumRadius)
            let candidate = RegionCandidate(key: boundaryID, title: "Boundary", subtitle: nil, center: user, radius: radius, symbol: "location", colorHex: "#8E8E93")
            boundary = PlannedRegion(id: boundaryID, candidate: candidate, startsInside: true)
        }
        return GeofencePlan(regions: regions, boundary: boundary)
    }

    /// Distance from you to the edge of a region; zero when inside.
    static func edgeDistance(from user: GeoPoint, to candidate: RegionCandidate) -> Double {
        max(0, user.distance(to: candidate.center) - candidate.radius)
    }

    static func regionID(for candidate: RegionCandidate) -> String {
        "\(candidate.key)|\(candidate.center.key)|\(Int(candidate.radius))"
    }

    private static func clamped(_ candidate: RegionCandidate) -> RegionCandidate {
        var copy = candidate
        copy.radius = min(max(candidate.radius, minimumRadius), maximumRadius)
        return copy
    }

    /// Merges the same place found twice (two searches returning one Tesco).
    private static func deduplicate(_ candidates: [RegionCandidate]) -> [RegionCandidate] {
        var kept: [RegionCandidate] = []
        for candidate in candidates {
            if let index = kept.firstIndex(where: { $0.key == candidate.key && $0.center.distance(to: candidate.center) < 30 }) {
                kept[index].radius = max(kept[index].radius, candidate.radius)
            } else {
                kept.append(candidate)
            }
        }
        return kept
    }
}
