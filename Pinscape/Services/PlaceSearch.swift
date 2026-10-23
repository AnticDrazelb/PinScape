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

    /// The closest branches of a chain, or places of a kind, around a location.
    func branches(for spec: PlaceSearchSpec, near location: CLLocation, radius: CLLocationDistance = 8_000, limit: Int = 8) async -> [RegionCandidate] {
        let here = GeoPoint(location.coordinate)
        if let entry = cache[spec.key], entry.center.distance(to: here) < 1_500, Date().timeIntervalSince(entry.date) < 12 * 60 * 60 {
            return entry.results
        }

        let items = await search(spec.query, near: location.coordinate, radius: radius, pointsOfInterestOnly: true)
        guard !items.isEmpty else { return cache[spec.key]?.results ?? [] }

        let category = spec.category ?? .other
        var results: [RegionCandidate] = []
        for item in items where spec.accepts(resultName: item.name ?? "") {
            let candidate = RegionCandidate(
                key: spec.key,
                title: item.name ?? spec.query,
                subtitle: Self.address(of: item),
                center: GeoPoint(item.placemark.coordinate),
                radius: PlaceTarget.storeRadius,
                symbol: category.symbol,
                colorHex: category.colorHex
            )
            results.append(candidate)
        }
        results.sort { $0.center.distance(to: here) < $1.center.distance(to: here) }
        results = Array(results.prefix(limit))

        cache[spec.key] = Entry(center: here, date: Date(), results: results)
        persist()
        return results
    }

    /// A plain Apple Maps search around a point.
    func search(_ query: String, near center: CLLocationCoordinate2D?, radius: CLLocationDistance = 10_000, pointsOfInterestOnly: Bool = false) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        }
        request.resultTypes = pointsOfInterestOnly ? .pointOfInterest : [.pointOfInterest, .address]
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems
        } catch {
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
