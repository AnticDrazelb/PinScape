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
        let candidates = (1...30).map { candidate("brand:tesco", north: Double($0) * 1_000) }
        let plan = GeofencePlanner.plan(candidates: candidates.shuffled(), around: london)

        XCTAssertEqual(plan.regions.count, 19)
        XCTAssertEqual(plan.all.count, 20)
        let farthest = plan.regions.map { $0.candidate.center.distance(to: london) }.max()!
        XCTAssertLessThan(farthest, 19_500)

        let boundary = try! XCTUnwrap(plan.boundary)
        // The 20th shop is ~20 km away less its 150 m radius; we must re-plan before reaching it.
        XCTAssertLessThanOrEqual(boundary.candidate.radius, 19_900)
        XCTAssertGreaterThan(boundary.candidate.radius, 19_000)
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
