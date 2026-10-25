import XCTest
#if canImport(PinscapeCore)
@testable import PinscapeCore
#endif

final class PlacesTests: XCTestCase {
    func testKeyVariants() {
        XCTAssertEqual(Set(TextNormalizer.keyVariants(of: "B&Q")), ["b&q", "b & q", "b and q"])
        XCTAssertTrue(TextNormalizer.keyVariants(of: "Marks and Spencer").contains("marks & spencer"))
        XCTAssertEqual(TextNormalizer.normalize("Sainsbury’s,"), "sainsburys")
        XCTAssertEqual(TextNormalizer.normalize("Caffè"), "caffe")
    }

    func testBrandLookup() {
        XCTAssertEqual(BrandCatalog.brand(named: "currys")?.name, "Currys")
        XCTAssertEqual(BrandCatalog.brand(named: "B & Q")?.name, "B&Q")
        XCTAssertEqual(BrandCatalog.brand(forHost: "www.diy.com")?.name, "B&Q")
        XCTAssertEqual(BrandCatalog.brand(forHost: "ikea.com")?.name, "IKEA")
        XCTAssertNil(BrandCatalog.brand(forHost: "example.com"))
    }

    func testSearchAcceptsOnlyTheBrand() {
        let tesco = PlaceTarget.brand(BrandCatalog.brand(named: "Tesco")!).searches[0]
        XCTAssertTrue(tesco.accepts(resultName: "Tesco Express"))
        XCTAssertTrue(tesco.accepts(resultName: "Tesco Superstore Camden"))
        XCTAssertFalse(tesco.accepts(resultName: "Sainsbury's Local"))
        let bp = PlaceTarget.brand(BrandCatalog.brand(named: "BP")!).searches[0]
        XCTAssertTrue(bp.accepts(resultName: "BP Connect"))
        XCTAssertFalse(bp.accepts(resultName: "Abbey Park"))
        let whsmith = PlaceTarget.brand(BrandCatalog.brand(named: "WHSmith")!).searches[0]
        XCTAssertTrue(whsmith.accepts(resultName: "WH Smith"))
    }

    func testSuggestionsFromNote() {
        let stain = PlaceSuggester.suggestions(for: "wood stain the dark one")
        XCTAssertEqual(stain.first?.title, "B&Q")
        XCTAssertTrue(stain.contains { $0.kind == .category(.hardware) })

        let meds = PlaceSuggester.suggestions(for: "Hay fever tablets and plasters")
        XCTAssertEqual(meds.first?.title, "Boots")

        let desk = PlaceSuggester.suggestions(for: "standing desk", market: .us)
        XCTAssertTrue(desk.contains { $0.kind == .category(.homeware) })

        XCTAssertTrue(PlaceSuggester.suggestions(for: "call dad").isEmpty)
    }

    func testBrandsInScreenshotText() {
        let text = """
        CURRYS
        Samsung 55" QLED TV
        £549 Save £150
        Free delivery from Currys
        """
        XCTAssertEqual(PlaceSuggester.brandsMentioned(in: text).first?.name, "Currys")
        XCTAssertTrue(PlaceSuggester.brandsMentioned(in: "comfy boots for winter").isEmpty)
    }

    func testRegionKeysMatchPins() {
        let tesco = PlaceTarget.brand(BrandCatalog.brand(named: "Tesco")!)
        XCTAssertTrue(tesco.matches(regionKey: "brand:tesco"))
        XCTAssertFalse(tesco.matches(regionKey: "brand:aldi"))

        let group = PlaceTarget.group(id: UUID(), name: "Supermarkets", members: ["Tesco", "Aldi"], symbol: "cart.fill", colorHex: "#34C759")
        XCTAssertTrue(group.matches(regionKey: "brand:aldi"))
        XCTAssertFalse(group.matches(regionKey: "brand:lidl"))

        let id = UUID()
        let gym = PlaceTarget.saved(id: id, name: "Gym", center: GeoPoint(latitude: 51.5, longitude: -0.1), radius: 150, symbol: "dumbbell.fill", colorHex: "#FF375F")
        let nearGym = PlaceTarget.saved(id: id, name: "Gym", center: GeoPoint(latitude: 51.5, longitude: -0.1), radius: 150, symbol: "dumbbell.fill", colorHex: "#FF375F", near: true)
        XCTAssertNotEqual(gym.fixedKey, nearGym.fixedKey)
        XCTAssertEqual(nearGym.radius, PlaceTarget.nearRadius)
        XCTAssertEqual(nearGym.title, "Near Gym")
    }

    func testNextVisitPinsSurfaceOnce() {
        let now = Date()
        let made = now.addingTimeInterval(-3600)
        XCTAssertTrue(SurfacingPolicy.shouldSurface(isAmbient: false, isCompleted: false, createdAt: made, lastSurfacedAt: nil, snoozedUntil: nil, now: now))
        // Already reminded you: disarmed, even days later.
        XCTAssertFalse(SurfacingPolicy.shouldSurface(isAmbient: false, isCompleted: false, createdAt: made, lastSurfacedAt: now.addingTimeInterval(-3 * 86_400), snoozedUntil: nil, now: now))
        XCTAssertFalse(SurfacingPolicy.isArmed(isAmbient: false, isCompleted: false, lastSurfacedAt: now))
        XCTAssertTrue(SurfacingPolicy.isArmed(isAmbient: false, isCompleted: false, lastSurfacedAt: nil))
    }

    func testEveryVisitPinsRestBetweenVisits() {
        let now = Date()
        let made = now.addingTimeInterval(-86_400 * 7)
        XCTAssertTrue(SurfacingPolicy.isArmed(isAmbient: true, isCompleted: false, lastSurfacedAt: now))
        XCTAssertFalse(SurfacingPolicy.shouldSurface(isAmbient: true, isCompleted: false, createdAt: made, lastSurfacedAt: now.addingTimeInterval(-3600), snoozedUntil: nil, now: now))
        XCTAssertTrue(SurfacingPolicy.shouldSurface(isAmbient: true, isCompleted: false, createdAt: made, lastSurfacedAt: now.addingTimeInterval(-86_400), snoozedUntil: nil, now: now))
        XCTAssertTrue(SurfacingPolicy.shouldSurface(isAmbient: true, isCompleted: false, createdAt: made, lastSurfacedAt: now.addingTimeInterval(-3600), snoozedUntil: nil, now: now, rest: 1800))
    }

    func testSurfacingGuards() {
        let now = Date()
        let made = now.addingTimeInterval(-3600)
        XCTAssertFalse(SurfacingPolicy.shouldSurface(isAmbient: false, isCompleted: true, createdAt: made, lastSurfacedAt: nil, snoozedUntil: nil, now: now))
        XCTAssertFalse(SurfacingPolicy.isArmed(isAmbient: true, isCompleted: true, lastSurfacedAt: nil))
        // Made a moment ago, standing right there.
        XCTAssertFalse(SurfacingPolicy.shouldSurface(isAmbient: false, isCompleted: false, createdAt: now.addingTimeInterval(-30), lastSurfacedAt: nil, snoozedUntil: nil, now: now))
        XCTAssertFalse(SurfacingPolicy.shouldSurface(isAmbient: false, isCompleted: false, createdAt: made, lastSurfacedAt: nil, snoozedUntil: now.addingTimeInterval(60), now: now))
    }

    func testBusinessNamesReadNaturally() {
        XCTAssertEqual(TextNormalizer.businessName("Boots Uk Limited - Birchwood Health Centre"), "Boots, Birchwood Health Centre")
        XCTAssertEqual(TextNormalizer.businessName("Tesco Express"), "Tesco Express")
        XCTAssertEqual(TextNormalizer.businessName("Primark"), "Primark")
        XCTAssertEqual(TextNormalizer.businessName("Screwfix Ltd"), "Screwfix")
        XCTAssertEqual(TextNormalizer.businessName("Limited"), "Limited", "a name that's only a suffix is left alone")
    }
}
