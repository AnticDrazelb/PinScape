import XCTest
#if canImport(PinscapeCore)
@testable import PinscapeCore
#endif

/// Regression tests for the geofence lifecycle: what gets watched, and what an arrival changes.
final class PinLifecycleTests: XCTestCase {
    private let now = Date()
    private let tesco = PlaceTarget.brand(BrandCatalog.brand(named: "Tesco")!)
    private let bench = PlaceTarget.spot(name: "This bench", center: GeoPoint(latitude: 51.535, longitude: -0.12))

    private func pin(_ target: PlaceTarget, ambient: Bool = false, surfaced: Date? = nil, completed: Bool = false, snoozedUntil: Date? = nil) -> PinSnapshot {
        PinSnapshot(id: UUID(), target: target, isAmbient: ambient, isCompleted: completed, createdAt: now.addingTimeInterval(-86_400), lastSurfacedAt: surfaced, snoozedUntil: snoozedUntil)
    }

    func testOnlyArmedPinsAreWatched() {
        let inputs = GeofencePlanner.inputs(for: [
            pin(tesco),
            pin(tesco), // same chain: one search
            pin(bench, surfaced: now), // next-visit, already reminded: no slot
            pin(bench, ambient: true, surfaced: now), // every visit: still watched
            pin(.brand(BrandCatalog.brand(named: "Aldi")!), completed: true),
        ])
        XCTAssertEqual(inputs.searches.map(\.key), ["brand:tesco"])
        XCTAssertEqual(inputs.fixed.count, 1)
    }

    func testOneTimePinReleasesItsRegionAfterSurfacing() {
        var oneTime = pin(bench)
        XCTAssertEqual(GeofencePlanner.inputs(for: [oneTime]).fixed.count, 1)

        let key = bench.fixedKey!
        let outcome = SurfacingPolicy.arrival(atRegionKey: key, pins: [oneTime], now: now)
        XCTAssertEqual(outcome.surface, [oneTime.id])
        XCTAssertTrue(outcome.disarms, "a next-visit pin surfacing must trigger a re-plan")

        oneTime.lastSurfacedAt = now
        XCTAssertTrue(GeofencePlanner.inputs(for: [oneTime]).fixed.isEmpty)
    }

    func testEveryVisitPinKeepsItsRegion() {
        var everyVisit = pin(bench, ambient: true)
        let outcome = SurfacingPolicy.arrival(atRegionKey: bench.fixedKey!, pins: [everyVisit], now: now)
        XCTAssertEqual(outcome.surface, [everyVisit.id])
        XCTAssertFalse(outcome.disarms)

        everyVisit.lastSurfacedAt = now
        XCTAssertEqual(GeofencePlanner.inputs(for: [everyVisit]).fixed.count, 1)
        // Back an hour later: resting, nothing surfaces.
        let soon = SurfacingPolicy.arrival(atRegionKey: bench.fixedKey!, pins: [everyVisit], now: now.addingTimeInterval(3600))
        XCTAssertTrue(soon.surface.isEmpty)
    }

    func testArrivalOnlyMatchesItsRegion() {
        let pins = [pin(tesco), pin(bench)]
        let atTesco = SurfacingPolicy.arrival(atRegionKey: "brand:tesco", pins: pins, now: now)
        XCTAssertEqual(atTesco.surface, [pins[0].id])
        XCTAssertTrue(SurfacingPolicy.arrival(atRegionKey: "brand:aldi", pins: pins, now: now).surface.isEmpty)
    }

    func testSnoozedAndCompletedPinsStayQuiet() {
        let pins = [pin(tesco, snoozedUntil: now.addingTimeInterval(600)), pin(tesco, completed: true)]
        let outcome = SurfacingPolicy.arrival(atRegionKey: "brand:tesco", pins: pins, now: now)
        XCTAssertTrue(outcome.surface.isEmpty)
        XCTAssertFalse(outcome.disarms)
    }
}
