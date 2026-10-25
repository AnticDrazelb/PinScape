import XCTest
#if canImport(PinscapeCore)
@testable import PinscapeCore
#endif

/// The "Show all branches" map layer: covering 50 miles with searches, and merging what they find.
final class BranchCoverageTests: XCTestCase {
    private let lincoln = GeoPoint(latitude: 53.2307, longitude: -0.5406)

    private func branch(_ key: String, north: Double, east: Double = 0) -> RegionCandidate {
        RegionCandidate(key: key, title: key, subtitle: nil, center: lincoln.offset(north: north, east: east), radius: 150, symbol: "cart.fill", colorHex: "#34C759")
    }

    func testTheGridCoversTheWholeCircle() {
        let radius = BranchCoverage.planningRadius
        let tiles = BranchCoverage.tiles(around: lincoln, radius: radius)
        XCTAssertEqual(tiles.count, 9)
        // Every point within 50 miles falls inside one of the squares.
        for bearing in stride(from: 0.0, to: 360, by: 15) {
            for fraction in [0.1, 0.5, 0.9, 1.0] {
                let north = cos(bearing * .pi / 180) * radius * fraction
                let east = sin(bearing * .pi / 180) * radius * fraction
                let point = lincoln.offset(north: north, east: east)
                let covered = tiles.contains { tile in
                    abs(point.latitude - tile.center.latitude) * 111_320 <= tile.halfSize + 1
                        && abs(point.longitude - tile.center.longitude) * 111_320 * cos(tile.center.latitude * .pi / 180) <= tile.halfSize + 1
                }
                XCTAssertTrue(covered, "\(Int(bearing))° at \(Int(fraction * 100))% of 50 miles isn't searched")
            }
        }
    }

    func testMergeKeepsEachBranchOnceNearestFirstAndWithinRange() {
        let near = branch("brand:boots", north: 2_000)
        let duplicate = branch("brand:boots", north: 2_020)
        let middle = branch("brand:boots", north: -30_000)
        let tooFar = branch("brand:boots", north: 95_000)
        let otherChain = branch("brand:primark", north: 2_010)

        let merged = BranchCoverage.merge([[middle, near], [duplicate, tooFar, otherChain]], around: lincoln, within: BranchCoverage.planningRadius)
        XCTAssertEqual(merged.map(\.key), ["brand:boots", "brand:primark", "brand:boots"])
        XCTAssertEqual(merged.first?.center, near.center, "nearest first, and the duplicate found by another search is dropped")
        XCTAssertFalse(merged.contains { $0.center == tooFar.center }, "nothing beyond 50 miles")
    }

    func testOffsetMovesTheRightDistance() {
        XCTAssertEqual(lincoln.distance(to: lincoln.offset(north: 10_000, east: 0)), 10_000, accuracy: 60)
        XCTAssertEqual(lincoln.distance(to: lincoln.offset(north: 0, east: -10_000)), 10_000, accuracy: 60)
    }
}
