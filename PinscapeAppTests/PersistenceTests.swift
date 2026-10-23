import SwiftData
import XCTest
@testable import Pinscape

/// The store a thought depends on: it survives a reopen, is shared between containers (as the app and
/// its extensions share it), and a damaged file is reported rather than replaced.
@MainActor
final class PersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var storeURL: URL { directory.appendingPathComponent("Pinscape.store") }

    private func tesco() -> PlaceTarget { .brand(BrandCatalog.brand(named: "Tesco")!) }

    func testPinsSurviveReopening() throws {
        do {
            let container = try PinStore.openPersistentContainer(at: storeURL)
            let context = ModelContext(container)
            context.insert(Pin(text: "Batteries", place: tesco(), isAmbient: true))
            try context.save()
        }
        let reopened = try PinStore.openPersistentContainer(at: storeURL)
        let pins = try ModelContext(reopened).fetch(FetchDescriptor<Pin>())
        XCTAssertEqual(pins.map(\.text), ["Batteries"])
        XCTAssertEqual(pins.first?.place.kind, .brand)
        XCTAssertEqual(pins.first?.place.name, "Tesco")
        XCTAssertEqual(pins.first?.isAmbient, true)
    }

    func testASaveInOneContainerIsVisibleInAnother() throws {
        let app = try PinStore.openPersistentContainer(at: storeURL)
        let shareExtension = try PinStore.openPersistentContainer(at: storeURL)
        let shareContext = ModelContext(shareExtension)
        shareContext.insert(Pin(text: "Desk from the screenshot", place: .brand(BrandCatalog.brand(named: "IKEA")!)))
        try shareContext.save()

        let seen = try ModelContext(app).fetch(FetchDescriptor<Pin>())
        XCTAssertEqual(seen.map(\.text), ["Desk from the screenshot"])
    }

    func testDamagedStoreIsReportedAndLeftAlone() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let garbage = Data(repeating: 0xAB, count: 4096)
        try garbage.write(to: storeURL)

        XCTAssertThrowsError(try PinStore.openPersistentContainer(at: storeURL))
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage, "the file must not be wiped or replaced")
    }

    func testUnreadablePlaceFallsBackToItsName() {
        let pin = Pin(text: "Glue", place: .search("Hobbycraft"))
        pin.placeData = Data("not json".utf8)
        XCTAssertEqual(pin.place.kind, .search)
        XCTAssertEqual(pin.place.name, "Hobbycraft")
    }
}
