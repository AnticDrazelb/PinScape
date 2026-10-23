import Foundation

/// What the planner and arrival logic need to know about a pin, independent of the database.
struct PinSnapshot: Sendable {
    var id: UUID
    /// The place, with any saved place's latest position already applied.
    var target: PlaceTarget
    var isAmbient: Bool
    var isCompleted: Bool
    var createdAt: Date
    var lastSurfacedAt: Date?
    var snoozedUntil: Date?

    var isArmed: Bool {
        SurfacingPolicy.isArmed(isAmbient: isAmbient, isCompleted: isCompleted, lastSurfacedAt: lastSurfacedAt)
    }
}

/// The places to hand the planner: fixed regions, plus searches for chains and kinds of place.
struct PlanInputs: Sendable {
    var fixed: [RegionCandidate]
    var searches: [PlaceSearchSpec]
}

/// What arriving in a region should do.
struct ArrivalOutcome: Equatable, Sendable {
    /// Pins to surface now.
    var surface: [UUID]
    /// Some of them were next-visit pins that are now disarmed, so the plan can release their places.
    var disarms: Bool
}

extension GeofencePlanner {
    /// Only armed pins need watching: a next-visit pin that already reminded you takes no slot.
    static func inputs(for pins: [PinSnapshot]) -> PlanInputs {
        var fixed: [RegionCandidate] = []
        var searches: [String: PlaceSearchSpec] = [:]
        for pin in pins where pin.isArmed {
            let target = pin.target
            if let key = target.fixedKey, let center = target.center {
                fixed.append(RegionCandidate(key: key, title: target.title, subtitle: target.kind == .spot ? target.detail : nil, center: center, radius: target.radius, symbol: target.symbol, colorHex: target.colorHex))
            }
            for spec in target.searches where searches[spec.key] == nil {
                searches[spec.key] = spec
            }
        }
        return PlanInputs(fixed: fixed, searches: searches.values.sorted { $0.key < $1.key })
    }
}

extension SurfacingPolicy {
    /// Decides which pins an arrival surfaces, and whether that changes what needs watching.
    static func arrival(atRegionKey key: String, pins: [PinSnapshot], now: Date, rest: TimeInterval = defaultRest) -> ArrivalOutcome {
        let due = pins.filter { pin in
            pin.target.matches(regionKey: key) && shouldSurface(isAmbient: pin.isAmbient, isCompleted: pin.isCompleted, createdAt: pin.createdAt, lastSurfacedAt: pin.lastSurfacedAt, snoozedUntil: pin.snoozedUntil, now: now, rest: rest)
        }
        return ArrivalOutcome(surface: due.map(\.id), disarms: due.contains { !$0.isAmbient })
    }
}
