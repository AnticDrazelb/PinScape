import CoreLocation
import Foundation
import Observation

/// The map's "Show all branches" layer: every branch of the chains and kinds of place your pins
/// are for, within 50 miles, to plan a trip around. Only shown; what's watched still follows you.
@MainActor
@Observable
final class AllBranchesModel {
    struct Place: Identifiable {
        var spec: PlaceSearchSpec
        var name: String
        var branches: [RegionCandidate]
        var id: String { spec.key }
    }

    private(set) var places: [Place] = []
    private(set) var isLoading = false
    /// False when Apple Maps couldn't be reached for some of them.
    private(set) var isComplete = true

    var total: Int { places.reduce(0) { $0 + $1.branches.count } }

    func load(_ specs: [PlaceSearchSpec], around location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }
        var loaded: [Place] = []
        var complete = true
        for spec in specs {
            let lookup = PinStore.isDemo
                ? BranchLookup(results: DemoContent.branches(for: spec), isFresh: true)
                : await PlaceSearch.shared.allBranches(for: spec, around: location)
            loaded.append(Place(spec: spec, name: Self.name(for: spec), branches: lookup.results))
            complete = complete && lookup.isFresh
            // Show each chain as it arrives.
            places = loaded
        }
        isComplete = complete
    }

    /// "Boots 23 · Primark 4 within 50 mi", or a total when there are many.
    var summary: String {
        if places.isEmpty {
            return isLoading ? "Finding branches…" : "No chains to show"
        }
        let found = places.filter { !$0.branches.isEmpty }
        let range = Locale.current.measurementSystem == .metric ? "80 km" : "50 mi"
        guard !found.isEmpty else { return isLoading ? "Finding branches…" : "None within \(range)" }
        let counts = found.count <= 3
            ? found.map { "\($0.name) \($0.branches.count)" }.joined(separator: " · ")
            : "\(total) branches of \(found.count) places"
        return "\(counts) within \(range)" + (isComplete || isLoading ? "" : " · some missing")
    }

    static func name(for spec: PlaceSearchSpec) -> String {
        spec.brandName ?? spec.category?.displayName ?? TextNormalizer.titleCase(spec.query)
    }
}
