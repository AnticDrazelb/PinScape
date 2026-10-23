import XCTest
@testable import Pinscape

/// Capture must never save to a stale or guessed place.
@MainActor
final class CaptureModelTests: XCTestCase {
    func testKnownPlacesResolveInstantly() {
        let model = CaptureModel(request: CaptureRequest(text: "Tesco, milk", listen: false))
        XCTAssertEqual(model.place?.name, "Tesco")
        XCTAssertFalse(model.isResolving)
        XCTAssertTrue(model.canSave)
    }

    func testChangingPlaceDropsTheOldOneWhileLookingUp() {
        let model = CaptureModel(request: CaptureRequest(text: "Tesco, milk", listen: false))
        XCTAssertEqual(model.place?.name, "Tesco")

        model.text = "milk at Camden Market"
        XCTAssertNil(model.place, "the previous place must not stay selected")
        XCTAssertTrue(model.isResolving)
        XCTAssertFalse(model.canSave)
    }

    func testSeveralMatchesWaitForYourChoice() {
        let model = CaptureModel(request: CaptureRequest(text: "glue at Hobbycraft", listen: false))
        let any = PlaceOption(target: .search("Hobbycraft"), title: "Any Hobbycraft", subtitle: "")
        let one = PlaceOption(target: .spot(name: "Hobbycraft Camden", center: GeoPoint(latitude: 51.54, longitude: -0.14)), title: "Hobbycraft Camden", subtitle: "")
        model.apply(.choose([any, one]))

        XCTAssertNil(model.place, "nothing is picked for you")
        XCTAssertTrue(model.needsChoice)
        XCTAssertEqual(model.save(), .notReady)

        model.choose(one.target)
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.place?.name, "Hobbycraft Camden")
    }

    func testChoosingAPlaceWinsOverALookupInFlight() {
        let model = CaptureModel(request: CaptureRequest(text: "milk at Camden Market", listen: false))
        XCTAssertTrue(model.isResolving)
        model.choose(.category(.supermarket))
        XCTAssertFalse(model.isResolving)
        XCTAssertTrue(model.canSave)
    }
}
