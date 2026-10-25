import XCTest
#if canImport(PinscapeCore)
@testable import PinscapeCore
#endif

final class GeofencePlannerTests: XCTestCase {
    private let london = GeoPoint(latitude: 51.5074, longitude: -0.1278)

    private func candidate(_ key: String, north metres: Double, radius: Double = 150) -> RegionCandidate {
        // ~111,111 m per degree of latitude
        let point = GeoPoint(latitude: london.latitude + metres / 111_111, longitude: london.longitude)
        return RegionCandidate(key: key, title: key, subtitle: nil, center: point, radius: radius, symbol: "cart.fill", colorHex: "#34C759")
    }

    func testKeepsTheNearestRegionsAndDrawsABoundary() {
        // 30 different places, all needed: the 19 nearest fit, with the boundary before the 20th.
        let candidates = (1...30).map { candidate("spot:\($0)", north: Double($0) * 1_000) }
        let plan = GeofencePlanner.plan(candidates: candidates.shuffled(), around: london)

        XCTAssertEqual(plan.regions.count, 19)
        XCTAssertEqual(plan.all.count, 20)
        let farthest = plan.regions.map { $0.candidate.center.distance(to: london) }.max()!
        XCTAssertLessThan(farthest, 19_500)

        let boundary = try! XCTUnwrap(plan.boundary)
        // The 20th place is ~20 km away less its 150 m radius; we must re-plan before reaching it.
        XCTAssertLessThanOrEqual(boundary.candidate.radius, 19_900)
        XCTAssertGreaterThan(boundary.candidate.radius, 19_000)
    }

    func testTwoChainsWatchOnlyWhatsWithinReach() {
        // Like two pins around Lincoln: Boots at 2–12 km, Primark only in town, 7 km and 9 km away.
        let boots = [2_000.0, 3_500, 4_200, 6_000, 8_000, 10_000, 12_000].map { candidate("brand:boots", north: $0) }
        let primark = [7_200.0, 9_000].map { candidate("brand:primark", north: -$0) }
        let plan = GeofencePlanner.plan(candidates: boots + primark, around: london, refreshDistance: 3_000)

        // Distances to the nearest 100 m (the helper's metres-per-degree is approximate).
        let watched = plan.regions.map { ($0.candidate.key, Int(($0.candidate.center.distance(to: london) / 100).rounded()) * 100) }
        XCTAssertEqual(watched.filter { $0.0 == "brand:boots" }.map(\.1), [2_000, 3_500, 4_200], "Boots within reach of the next re-plan")
        XCTAssertEqual(watched.filter { $0.0 == "brand:primark" }.map(\.1), [7_200], "the nearest Primark, though it's far, so the pin is armed")
        XCTAssertEqual(plan.all.count, 5, "4 shops and the boundary, not 9 shops")
        XCTAssertEqual(plan.boundary?.candidate.radius, 3_000)
    }

    func testAtMostFiveBranchesOfOnePlace() {
        let tescos = (1...12).map { candidate("brand:tesco", north: Double($0) * 200) }
        let plan = GeofencePlanner.plan(candidates: tescos, around: london, refreshDistance: 3_000)
        XCTAssertEqual(plan.regions.count, GeofencePlanner.branchesPerPlace)
        // The 6th Tesco, 1.2 km away, isn't watched, so the boundary comes before it.
        XCTAssertEqual(plan.boundary!.candidate.radius, 1_200 - 150, accuracy: 2)
    }

    func testNothingLeftOutIsInsideTheBoundary() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let keys = ["brand:tesco", "brand:boots", "brand:aldi", "category:pharmacy", "spot:bench"]
            let candidates = (0..<40).map { _ in
                candidate(keys.randomElement(using: &generator)!, north: Double.random(in: -15_000...15_000, using: &generator))
            }
            let plan = GeofencePlanner.plan(candidates: candidates, around: london, refreshDistance: 3_000)
            let watched = Set(plan.regions.map(\.id))
            let boundary = try! XCTUnwrap(plan.boundary).candidate.radius
            XCTAssertLessThanOrEqual(plan.all.count, GeofencePlanner.regionLimit)
            // Same-place candidates within 30 m are merged into one region, so they count as watched.
            let merged = { (left: RegionCandidate) in plan.regions.contains { $0.candidate.key == left.key && $0.candidate.center.distance(to: left.center) < 30 } }
            for left in candidates where !watched.contains(GeofencePlanner.regionID(for: left)) && !merged(left) {
                let edge = GeofencePlanner.edgeDistance(from: london, to: left)
                XCTAssertGreaterThanOrEqual(edge + 1, boundary, "an unwatched place must lie beyond the boundary")
            }
            for key in Set(candidates.map(\.key)) {
                XCTAssertTrue(plan.regions.contains { $0.candidate.key == key } || plan.regions.count == GeofencePlanner.regionLimit - 1, "every place keeps at least its nearest branch")
            }
        }
    }

    func testEverythingFitsWithoutBoundaryWhenStatic() {
        let candidates = [candidate("saved:a", north: 500), candidate("spot:b", north: 2_000)]
        let plan = GeofencePlanner.plan(candidates: candidates, around: london)
        XCTAssertEqual(plan.regions.count, 2)
        XCTAssertNil(plan.boundary)
    }

    func testRefreshDistanceAddsBoundary() {
        let plan = GeofencePlanner.plan(candidates: [candidate("brand:tesco", north: 800)], around: london, refreshDistance: 3_000)
        XCTAssertEqual(plan.boundary?.candidate.radius, 3_000)
    }

    func testMarksRegionsYouAreAlreadyIn() {
        let plan = GeofencePlanner.plan(candidates: [candidate("brand:tesco", north: 50), candidate("brand:aldi", north: 900)], around: london)
        XCTAssertEqual(plan.regions.first { $0.candidate.key == "brand:tesco" }?.startsInside, true)
        XCTAssertEqual(plan.regions.first { $0.candidate.key == "brand:aldi" }?.startsInside, false)
    }

    func testDeduplicatesAndClampsRadius() {
        let a = candidate("brand:tesco", north: 1_000, radius: 20)
        var b = a
        b.center.latitude += 0.0001 // ~11 m
        let plan = GeofencePlanner.plan(candidates: [a, b], around: london)
        XCTAssertEqual(plan.regions.count, 1)
        XCTAssertEqual(plan.regions[0].candidate.radius, GeofencePlanner.minimumRadius)
    }

    func testWithoutLocationKeepsPriorityOrder() {
        let candidates = (1...25).map { candidate("spot:\($0)", north: Double($0) * 100) }
        let plan = GeofencePlanner.plan(candidates: candidates, around: nil)
        XCTAssertEqual(plan.regions.count, 20)
        XCTAssertEqual(plan.regions.first?.candidate.key, "spot:1")
        XCTAssertNil(plan.boundary)
    }
}
