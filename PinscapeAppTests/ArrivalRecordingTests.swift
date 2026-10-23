import SwiftData
import XCTest
@testable import Pinscape

/// A reminder is shown only once the fact that it was shown is saved, so a failed save can't lead
/// to a reminder that repeats, and a successful one can't be lost.
@MainActor
final class ArrivalRecordingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var region: PlannedRegion!

    private struct DiskFull: Error {}

    override func setUpWithError() throws {
        let memory = ModelConfiguration(schema: PinStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: PinStore.schema, configurations: [memory])
        context = ModelContext(container)
        let candidate = RegionCandidate(key: "brand:tesco", title: "Tesco Express", subtitle: nil, center: GeoPoint(latitude: 51.53, longitude: -0.12), radius: 150, symbol: "cart.fill", colorHex: "#00A651")
        region = PlannedRegion(id: GeofencePlanner.regionID(for: candidate), candidate: candidate, startsInside: false)
    }

    @discardableResult
    private func addPin(_ text: String, ambient: Bool = false) throws -> Pin {
        let pin = Pin(text: text, place: .brand(BrandCatalog.brand(named: "Tesco")!), isAmbient: ambient)
        pin.createdAt = Date().addingTimeInterval(-3_600)
        context.insert(pin)
        try context.save()
        return pin
    }

    private func record(save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ArrivalCoordinator.RecordedArrival {
        try ArrivalCoordinator.record(arrivalAt: region, now: Date(), in: context, rest: SurfacingPolicy.defaultRest, save: save)
    }

    /// What another process (or the next launch) would read.
    private func surfacedTimes() throws -> [Date?] {
        try ModelContext(container).fetch(FetchDescriptor<Pin>()).map(\.lastSurfacedAt)
    }

    func testAnArrivalIsSavedBeforeItIsAnnounced() throws {
        try addPin("Batteries")
        try addPin("Bin bags", ambient: true)
        let recorded = try record()
        XCTAssertEqual(Set(recorded.pins.map(\.text)), ["Batteries", "Bin bags"])
        XCTAssertTrue(recorded.disarms, "a next-visit pin surfaced, so its place can be released")
        XCTAssertTrue(try surfacedTimes().allSatisfy { $0 != nil }, "the surfacing is on disk before anything is shown")
    }

    func testASecondArrivalDoesNotRepeatTheReminder() throws {
        try addPin("Batteries")
        XCTAssertEqual(try record().pins.count, 1)
        XCTAssertTrue(try record().pins.isEmpty)
    }

    func testAFailedSaveAnnouncesNothingAndLeavesThePinsDue() throws {
        let pin = try addPin("Batteries")
        XCTAssertThrowsError(try record(save: { _ in throw DiskFull() }))
        XCTAssertNil(pin.lastSurfacedAt, "the change is rolled back")
        XCTAssertEqual(pin.surfaceCount, 0)
        XCTAssertEqual(try surfacedTimes(), [nil])

        // The retry, once saving works again, still reminds you.
        XCTAssertEqual(try record().pins.map(\.text), ["Batteries"])
    }

    func testNothingDueRecordsNothing() throws {
        let pin = try addPin("Batteries")
        pin.snoozedUntil = Date().addingTimeInterval(600)
        try context.save()
        XCTAssertTrue(try record(save: { _ in XCTFail("nothing to save") }).pins.isEmpty)
    }
}
