import Foundation

/// What one Apple Maps search for a chain or kind of place returned.
struct BranchLookup: Sendable {
    var results: [RegionCandidate]
    /// False when Apple Maps couldn't be reached and older results (or none) were used instead.
    var isFresh: Bool
}

/// A plan, and whether everything that should be watched could be worked out.
struct ReplanResult: Sendable {
    var plan: GeofencePlan
    /// False when a search failed or there was no location fix: plan again later.
    var isComplete: Bool
}

extension GeofencePlanner {
    /// Plans from what's known now without dropping places that were working a moment ago.
    ///
    /// A chain or kind of place whose search failed, or couldn't run for want of a location fix,
    /// keeps the branches it had last time (plus any cached ones) until a search succeeds. Without
    /// a fix nothing can be ranked afresh, so the places already watched come first and the old
    /// boundary stays put: redrawing it around nowhere would only wake Pinscape to fail again.
    /// Places no armed pin needs any more are always released.
    ///
    /// - Parameters:
    ///   - lookups: search results by `PlaceSearchSpec.key`; a missing entry means it wasn't searched.
    ///   - previous: the plan being replaced, boundary included.
    static func replan(inputs: PlanInputs, lookups: [String: BranchLookup], previous: [PlannedRegion], around user: GeoPoint?, refreshDistance: Double = 3_000) -> ReplanResult {
        let watched = previous.filter { $0.id != boundaryID }
        var candidates = inputs.fixed
        var isComplete = true
        for spec in inputs.searches {
            if let lookup = lookups[spec.key], lookup.isFresh {
                candidates += lookup.results
            } else {
                isComplete = false
                candidates += watched.filter { $0.candidate.key == spec.key }.map(\.candidate)
                candidates += lookups[spec.key]?.results ?? []
            }
        }

        if let user {
            let planned = plan(candidates: candidates, around: user, refreshDistance: inputs.searches.isEmpty ? nil : refreshDistance)
            return ReplanResult(plan: planned, isComplete: isComplete)
        }

        // Last time's places were the nearest when there was a fix, so they keep their slots.
        let watchedPlaces = Set(watched.map { placeKey(for: $0.candidate) })
        let ordered = candidates.filter { watchedPlaces.contains(placeKey(for: $0)) } + candidates.filter { !watchedPlaces.contains(placeKey(for: $0)) }
        let boundary = previous.first { $0.id == boundaryID }
        var planned = plan(candidates: ordered, around: nil, limit: boundary == nil ? regionLimit : regionLimit - 1)
        planned.boundary = boundary
        return ReplanResult(plan: planned, isComplete: isComplete)
    }

    private static func placeKey(for candidate: RegionCandidate) -> String {
        "\(candidate.key)|\(candidate.center.key)"
    }
}
