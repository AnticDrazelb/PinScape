import Foundation

/// Finding every branch across a wide area, for planning a trip on the map. Apple Maps returns
/// only a couple of dozen results per search, so one search covers the whole area and, if that
/// came back full, a grid of smaller searches fills in the rest.
enum BranchCoverage {
    /// 50 miles.
    static let planningRadius = 80_467.0
    /// A search that returns this many places probably stopped short of them all.
    static let fullResultCount = 8

    struct Tile: Equatable {
        var center: GeoPoint
        /// Half the side of the square searched.
        var halfSize: Double
    }

    /// Nine squares in a 3 × 3 grid that together cover the circle.
    static func tiles(around center: GeoPoint, radius: Double) -> [Tile] {
        let step = radius * 2 / 3
        var tiles: [Tile] = []
        for row in -1...1 {
            for column in -1...1 {
                tiles.append(Tile(center: center.offset(north: Double(row) * step, east: Double(column) * step), halfSize: step / 2))
            }
        }
        return tiles
    }

    /// Every branch found, once, within the radius, nearest first.
    static func merge(_ results: [[RegionCandidate]], around center: GeoPoint, within radius: Double) -> [RegionCandidate] {
        var kept: [RegionCandidate] = []
        for candidate in results.joined() where center.distance(to: candidate.center) <= radius {
            let seen = kept.contains { $0.key == candidate.key && $0.center.distance(to: candidate.center) < 50 }
            if !seen {
                kept.append(candidate)
            }
        }
        return kept.sorted { center.distance(to: $0.center) < center.distance(to: $1.center) }
    }
}

extension GeoPoint {
    /// The point this many metres north and east (negative for south and west).
    func offset(north: Double, east: Double) -> GeoPoint {
        let metresPerDegreeLatitude = 111_320.0
        let metresPerDegreeLongitude = max(111_320 * cos(latitude * .pi / 180), 1)
        return GeoPoint(latitude: latitude + north / metresPerDegreeLatitude, longitude: longitude + east / metresPerDegreeLongitude)
    }
}
