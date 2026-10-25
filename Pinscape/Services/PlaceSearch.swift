import CoreLocation
import Foundation
import MapKit

/// Apple Maps lookups, with a small on-device cache so moving around doesn't repeat searches.
@MainActor
final class PlaceSearch {
    static let shared = PlaceSearch()

    private struct Entry: Codable {
        var center: GeoPoint
        var date: Date
        var results: [RegionCandidate]
    }

    private var cache: [String: Entry] = [:]

    private init() {
        if let data = AppGroup.defaults.data(forKey: SharedKeys.searchCache),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = saved
        }
    }

    /// Older results are only worth reusing if they're from around here and not too old.
    private static let staleReuseDistance: Double = 5_000
    private static let staleReuseAge: TimeInterval = 3 * 24 * 60 * 60

    /// The closest branches of a chain, or places of a kind, around a location.
    func branches(for spec: PlaceSearchSpec, near location: CLLocation, radius: CLLocationDistance = 16_000, limit: Int = 8) async -> BranchLookup {
        let here = GeoPoint(location.coordinate)
        if let entry = cache[spec.key], entry.center.distance(to: here) < 1_500, Date().timeIntervalSince(entry.date) < 12 * 60 * 60 {
            return BranchLookup(results: entry.results, isFresh: true)
        }

        let items: [MKMapItem]
        do {
            items = try await searchItems(spec.query, near: location.coordinate, radius: radius, pointsOfInterestOnly: true)
        } catch {
            // Couldn't search (offline, throttled). A recent nearby answer beats nothing; an old or
            // far-away one would watch the wrong shops.
            Diagnostics.record(.searchFailed, "\(spec.key.split(separator: ":").first ?? ""): \(error.localizedDescription)")
            if let entry = cache[spec.key], entry.center.distance(to: here) < Self.staleReuseDistance, Date().timeIntervalSince(entry.date) < Self.staleReuseAge {
                return BranchLookup(results: entry.results, isFresh: false)
            }
            return BranchLookup(results: [], isFresh: false)
        }

        var results = candidates(from: items, for: spec)
        results.sort { $0.center.distance(to: here) < $1.center.distance(to: here) }
        results = Array(results.prefix(limit))

        // A real "none near here" is an answer too, and is cached like any other.
        cache[spec.key] = Entry(center: here, date: Date(), results: results)
        persist()
        return BranchLookup(results: results, isFresh: true)
    }

    /// Every branch of a chain or kind of place within a wide area (50 miles), for planning on the
    /// map. Nothing here is watched. Cached for a day while you stay within 10 km.
    func allBranches(for spec: PlaceSearchSpec, around location: CLLocation, within radius: CLLocationDistance = BranchCoverage.planningRadius) async -> BranchLookup {
        let here = GeoPoint(location.coordinate)
        if let entry = wideCache[spec.key], entry.center.distance(to: here) < 10_000, Date().timeIntervalSince(entry.date) < 24 * 60 * 60 {
            return BranchLookup(results: entry.results, isFresh: true)
        }
        var found: [[RegionCandidate]] = []
        var complete = true
        do {
            let whole = try await searchItems(spec.query, near: location.coordinate, radius: radius, pointsOfInterestOnly: true)
            found.append(candidates(from: whole, for: spec))
            if whole.count >= BranchCoverage.fullResultCount {
                for tile in BranchCoverage.tiles(around: here, radius: radius) {
                    let items = try await searchItems(spec.query, near: tile.center.coordinate, radius: tile.halfSize, pointsOfInterestOnly: true)
                    found.append(candidates(from: items, for: spec))
                }
            }
        } catch {
            // Throttled or offline part-way: show what was found.
            complete = false
        }
        let merged = BranchCoverage.merge(found, around: here, within: radius)
        if complete {
            wideCache[spec.key] = Entry(center: here, date: Date(), results: merged)
        }
        return BranchLookup(results: merged, isFresh: complete)
    }

    private var wideCache: [String: Entry] = [:]

    private func candidates(from items: [MKMapItem], for spec: PlaceSearchSpec) -> [RegionCandidate] {
        let category = spec.category ?? .other
        return items.filter { spec.accepts(resultName: $0.name ?? "") }.map { item in
            RegionCandidate(
                key: spec.key,
                title: TextNormalizer.businessName(item.name ?? spec.query),
                subtitle: Self.address(of: item),
                center: GeoPoint(item.placemark.coordinate),
                radius: PlaceTarget.storeRadius,
                symbol: category.symbol,
                colorHex: category.colorHex
            )
        }
    }

    /// A plain Apple Maps search around a point. Errors become an empty list; use `searchItems` to tell them apart.
    func search(_ query: String, near center: CLLocationCoordinate2D?, radius: CLLocationDistance = 10_000, pointsOfInterestOnly: Bool = false) async -> [MKMapItem] {
        (try? await searchItems(query, near: center, radius: radius, pointsOfInterestOnly: pointsOfInterestOnly)) ?? []
    }

    /// An Apple Maps search that returns an empty list when nothing matches, and throws when the search itself failed.
    func searchItems(_ query: String, near center: CLLocationCoordinate2D?, radius: CLLocationDistance = 10_000, pointsOfInterestOnly: Bool = false) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        }
        request.resultTypes = pointsOfInterestOnly ? .pointOfInterest : [.pointOfInterest, .address]
        do {
            return try await MKLocalSearch(request: request).start().mapItems
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    func clearCache() {
        cache = [:]
        persist()
    }

    private func persist() {
        // Keep the cache small: the 40 most recent searches.
        if cache.count > 40 {
            let keep = cache.sorted { $0.value.date > $1.value.date }.prefix(40)
            cache = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        AppGroup.defaults.set(try? JSONEncoder().encode(cache), forKey: SharedKeys.searchCache)
    }

    static func address(of item: MKMapItem) -> String? {
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, placemark.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
