import XCTest
#if canImport(PinscapeCore)
@testable import PinscapeCore
#endif

final class CaptureParserTests: XCTestCase {
    private let parser = CaptureParser(savedPlaceNames: ["Gym", "Mum's house", "Office"])

    private func assertParse(_ input: String, note: String, place: String?, match: PlaceMatch? = nil, near: Bool = false, ambient: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let result = parser.parse(input)
        XCTAssertEqual(result.note, note, "note for “\(input)”", file: file, line: line)
        XCTAssertEqual(result.place?.text, place, "place for “\(input)”", file: file, line: line)
        if let match {
            XCTAssertEqual(result.place?.match, match, "match for “\(input)”", file: file, line: line)
        }
        XCTAssertEqual(result.place?.isNear ?? false, near, "near for “\(input)”", file: file, line: line)
        XCTAssertEqual(result.isAmbient, ambient, "ambient for “\(input)”", file: file, line: line)
    }

    func testPlaceThenThought() {
        assertParse("Tesco, batteries", note: "Batteries", place: "Tesco")
        assertParse("Tesco, batteries.", note: "Batteries", place: "Tesco")
        assertParse("B&Q: wood stain, the dark one", note: "Wood stain, the dark one", place: "B&Q")
        assertParse("B&Q, wood stain — the dark one", note: "Wood stain — the dark one", place: "B&Q")
        assertParse("B and Q - wood stain the dark one", note: "Wood stain the dark one", place: "B&Q")
        assertParse("Sainsbury's, birthday candles", note: "Birthday candles", place: "Sainsbury's")
        assertParse("Curry's: ask about the TV deal", note: "Ask about the TV deal", place: "Currys")
    }

    func testThoughtThenPlace() {
        assertParse("wood stain the dark one at B&Q", note: "Wood stain the dark one", place: "B&Q")
        assertParse("wood stain — the dark one at B&Q", note: "Wood stain — the dark one", place: "B&Q")
        assertParse("buy batteries at Tesco", note: "Buy batteries", place: "Tesco")
        assertParse("batteries, Tesco", note: "Batteries", place: "Tesco")
        assertParse("pick up the parcel at the post office", note: "Pick up the parcel", place: "Post office", match: .category(.postOffice))
        assertParse("measure the alcove when I get to IKEA", note: "Measure the alcove", place: "IKEA")
    }

    func testLeadingTrigger() {
        assertParse("at B&Q wood stain the dark one", note: "Wood stain the dark one", place: "B&Q")
        assertParse("when I'm at Tesco buy milk", note: "Buy milk", place: "Tesco")
        assertParse("remind me at Tesco to buy batteries", note: "Buy batteries", place: "Tesco")
        assertParse("next time I'm in IKEA, get the meatballs", note: "Get the meatballs", place: "IKEA")
    }

    func testNoPunctuationDictation() {
        assertParse("Tesco batteries", note: "Batteries", place: "Tesco")
        assertParse("batteries Tesco", note: "Batteries", place: "Tesco")
    }

    func testSavedPlacesAndNear() {
        assertParse("near gym, book a PT session", note: "Book a PT session", place: "Gym", match: .saved("Gym"), near: true)
        assertParse("at Mum's water the plants", note: "Water the plants", place: "Mum's house", match: .saved("Mum's house"))
        assertParse("bring the charger to the office", note: "Bring the charger", place: "Office", match: .saved("Office"))
    }

    func testHereAndAmbient() {
        assertParse("this bench = call dad", note: "Call dad", place: "This bench", match: .here, ambient: true)
        assertParse("call dad when I'm at this bench", note: "Call dad", place: "This bench", match: .here)
        assertParse("creative ideas happen here", note: "Creative ideas happen here", place: "Here", match: .here)
        assertParse("Pub near office = creative ideas happen here", note: "Creative ideas happen here", place: "Pub", match: .category(.pub), ambient: true)
        XCTAssertEqual(parser.parse("Pub near office = creative ideas happen here").place?.anchor, "office")
    }

    func testFuzzyAreasAndFreeform() {
        assertParse("downtown, return the library book", note: "Return the library book", place: "Downtown", match: .downtown)
        assertParse("Bristol: try the bakery Sarah mentioned", note: "Try the bakery Sarah mentioned", place: "Bristol", match: .freeform)
        assertParse("try the bakery Sarah mentioned when I'm in Bristol", note: "Try the bakery Sarah mentioned", place: "Bristol", match: .freeform)
        assertParse("any pharmacy: hay fever tablets", note: "Hay fever tablets", place: "Pharmacy", match: .category(.pharmacy))
    }

    func testThoughtsWithoutPlaces() {
        assertParse("Milk, eggs, bread", note: "Milk, eggs, bread", place: nil)
        assertParse("look at the stars", note: "Look at the stars", place: nil)
        assertParse("Dad, call about Sunday", note: "Dad, call about Sunday", place: nil)
        assertParse("put the kettle on at 6", note: "Put the kettle on at 6", place: nil)
    }

    func testCommonWordBrands() {
        assertParse("buy new boots", note: "Buy new boots", place: nil)
        assertParse("hay fever tablets at Boots", note: "Hay fever tablets", place: "Boots")
        assertParse("Boots, hay fever tablets", note: "Hay fever tablets", place: "Boots")
    }

    func testConfirmationPhrase() {
        XCTAssertEqual(SurfacingPolicy.confirmation(place: "Tesco", note: "Batteries"), "Got it. Tesco, batteries.")
        XCTAssertEqual(SurfacingPolicy.confirmation(place: "B&Q", note: ""), "Got it. B&Q.")
    }

    func testMisheardBuyIsCorrected() {
        let parser = CaptureParser(savedPlaceNames: [])
        XCTAssertEqual(parser.parse("By paracetamol at Boots").note, "Buy paracetamol")
        XCTAssertEqual(parser.parse("Boots, by plasters").note, "Buy plasters")
        XCTAssertEqual(CaptureParser.cleanNote("by Friday send the forms"), "By Friday send the forms")
        XCTAssertEqual(CaptureParser.cleanNote("by the door, umbrella"), "By the door, umbrella")
        XCTAssertEqual(CaptureParser.cleanNote("by 5 call the vet"), "By 5 call the vet")
    }
}
