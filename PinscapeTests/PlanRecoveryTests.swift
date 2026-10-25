import XCTest
#if canImport(PinscapeCore)
@testable import PinscapeCore
#endif

/// A temporary Maps or location failure must never disarm reminders that were working.
final class PlanRecoveryTests: XCTestCase {
    private let kingsCross = GeoPoint(latitude: 51.5316, longitude: -0.1236)
    private let now = Date()

    private func pin(_ target: PlaceTarget) -> PinSnapshot {
        PinSnapshot(id: UUID(), target: target, isAmbient: false, isCompleted: false, createdAt: now.addingTimeInterval(-3_600), lastSurfacedAt: nil, snoozedUntil: nil)
    }

    private func brand(_ name: String) -> PlaceTarget {
        .brand(BrandCatalog.brand(named: name)!)
    }

    private func branch(_ key: String, _ title: String, _ north: Double, _ east: Double = 0) -> RegionCandidate {
        RegionCandidate(key: key, title: title, subtitle: nil, center: GeoPoint(latitude: kingsCross.latitude + north, longitude: kingsCross.longitude + east), radius: 150, symbol: "cart.fill", colorHex: "#00A651")
    }

    private func ids(_ result: ReplanResult) -> Set<String> {
        Set(result.plan.regions.map(\.id))
    }

    private let tescoKey = "brand:tesco"
    private lazy var tescoInputs = GeofencePlanner.inputs(for: [pin(brand("Tesco"))])
    private lazy var camden = branch(tescoKey, "Tesco Camden", 0.004)
    private lazy var angel = branch(tescoKey, "Tesco Angel", 0.0, 0.01)

    private func working() -> ReplanResult {
        GeofencePlanner.replan(inputs: tescoInputs, lookups: [tescoKey: BranchLookup(results: [camden, angel], isFresh: true)], previous: [], around: kingsCross)
    }

    func testAWorkingPlanIsComplete() {
        let result = working()
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.plan.regions.map(\.candidate.title).sorted(), ["Tesco Angel", "Tesco Camden"])
        XCTAssertNotNil(result.plan.boundary)
    }

    func testGoingOfflineKeepsTheBranchesAlreadyWatched() {
        let before = working()
        let offline = GeofencePlanner.replan(inputs: tescoInputs, lookups: [tescoKey: BranchLookup(results: [], isFresh: false)], previous: before.plan.all, around: kingsCross)
        XCTAssertFalse(offline.isComplete, "a failed search must be retried")
        XCTAssertEqual(ids(offline), ids(before), "a failed search mustn't disarm working branches")
    }

    func testCachedResultsJoinTheBranchesAlreadyWatched() {
        let before = working()
        let euston = branch(tescoKey, "Tesco Euston", -0.003, -0.01)
        let offline = GeofencePlanner.replan(inputs: tescoInputs, lookups: [tescoKey: BranchLookup(results: [euston], isFresh: false)], previous: before.plan.all, around: kingsCross)
        XCTAssertEqual(offline.plan.regions.map(\.candidate.title).sorted(), ["Tesco Angel", "Tesco Camden", "Tesco Euston"])
    }

    func testNoLocationFixKeepsWatchedPlacesAndTheirBoundary() {
        let before = working()
        let noFix = GeofencePlanner.replan(inputs: tescoInputs, lookups: [:], previous: before.plan.all, around: nil)
        XCTAssertFalse(noFix.isComplete)
        XCTAssertEqual(ids(noFix), ids(before))
        XCTAssertEqual(noFix.plan.boundary, before.plan.boundary, "the old boundary stays until there's a fix to redraw it around")
    }

    func testASuccessfulSearchAfterAFailureReplacesTheKeptBranches() {
        let offline = GeofencePlanner.replan(inputs: tescoInputs, lookups: [tescoKey: BranchLookup(results: [], isFresh: false)], previous: working().plan.all, around: kingsCross)
        let kentish = branch(tescoKey, "Tesco Kentish Town", 0.02)
        let recovered = GeofencePlanner.replan(inputs: tescoInputs, lookups: [tescoKey: BranchLookup(results: [kentish], isFresh: true)], previous: offline.plan.all, around: kingsCross)
        XCTAssertTrue(recovered.isComplete)
        XCTAssertEqual(recovered.plan.regions.map(\.candidate.title), ["Tesco Kentish Town"], "fresh results are the truth, even when they differ")
    }

    func testFinishedPinsReleaseTheirPlacesEvenOffline() {
        let both = GeofencePlanner.inputs(for: [pin(brand("Tesco")), pin(brand("Boots"))])
        let boots = branch("brand:boots", "Boots St Pancras", -0.001)
        let before = GeofencePlanner.replan(inputs: both, lookups: [tescoKey: BranchLookup(results: [camden], isFresh: true), "brand:boots": BranchLookup(results: [boots], isFresh: true)], previous: [], around: kingsCross)
        XCTAssertEqual(before.plan.regions.count, 2)

        // The Boots pin is done; Apple Maps is unreachable.
        let after = GeofencePlanner.replan(inputs: tescoInputs, lookups: [tescoKey: BranchLookup(results: [], isFresh: false)], previous: before.plan.all, around: kingsCross)
        XCTAssertEqual(after.plan.regions.map(\.candidate.title), ["Tesco Camden"])
    }

    func testNoLocationFixStaysWithinTheRegionLimit() {
        let spots = (0..<30).map { pin(.spot(name: "Spot \($0)", center: GeoPoint(latitude: kingsCross.latitude + Double($0) * 0.002, longitude: kingsCross.longitude))) }
        let before = GeofencePlanner.replan(inputs: GeofencePlanner.inputs(for: spots), lookups: [:], previous: [], around: kingsCross)
        XCTAssertEqual(before.plan.all.count, GeofencePlanner.regionLimit)

        let more = (0..<4).map { pin(.spot(name: "New \($0)", center: GeoPoint(latitude: 51.6 + Double($0) * 0.01, longitude: -0.2))) }
        let noFix = GeofencePlanner.replan(inputs: GeofencePlanner.inputs(for: spots + more), lookups: [:], previous: before.plan.all, around: nil)
        XCTAssertEqual(noFix.plan.all.count, GeofencePlanner.regionLimit)
        XCTAssertEqual(ids(noFix), ids(before), "the places already watched keep their slots until there's a fix to rank by")
    }
}
