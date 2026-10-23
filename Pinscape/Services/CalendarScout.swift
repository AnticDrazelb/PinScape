import CoreLocation
import EventKit
import Foundation
import Observation

/// An upcoming trip found in your calendar: "Bristol · Saturday".
struct TripSuggestion: Identifiable, Hashable {
    var id: String
    var eventTitle: String
    var city: String
    var date: Date
    var center: GeoPoint
}

/// Reads your calendar on device to spot trips (looking up an event's location in Apple Maps
/// when it has no coordinates), so Pinscape can ask
/// "You're going to Bristol on Saturday. Any pins to drop?"
@MainActor
@Observable
final class CalendarScout {
    static let shared = CalendarScout()

    private(set) var trips: [TripSuggestion] = []

    private let store = EKEventStore()

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var isAuthorized: Bool { status == .fullAccess }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted { await refresh() }
        return granted
    }

    func refresh() async {
        guard isAuthorized else {
            trips = []
            return
        }
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 10, to: start) else { return }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        let dismissed = Set(AppGroup.defaults.stringArray(forKey: SharedKeys.dismissedTrips) ?? [])
        let home = homePoint()

        var found: [TripSuggestion] = []
        var looked = 0
        for event in events {
            guard let id = event.eventIdentifier, !dismissed.contains(id) else { continue }
            var location = event.structuredLocation?.geoLocation
            if location == nil, let text = event.location, !text.isEmpty, looked < 6 {
                looked += 1
                location = await PlaceSearch.shared.search(text, near: home?.coordinate, radius: 50_000).first?.placemark.location
            }
            guard let location else { continue }
            let point = GeoPoint(location.coordinate)
            if let home, point.distance(to: home) < 25_000 { continue }
            let city = await PlaceResolver.townName(for: location) ?? event.location ?? event.title ?? "your trip"
            guard !found.contains(where: { $0.city == city }) else { continue }
            found.append(TripSuggestion(id: id, eventTitle: event.title ?? city, city: city, date: event.startDate, center: point))
        }
        trips = Array(found.prefix(3))
        for trip in trips {
            await NotificationManager.scheduleTripNudge(id: trip.id, city: trip.city, eventDate: trip.date)
        }
    }

    func dismiss(_ trip: TripSuggestion) {
        var dismissed = AppGroup.defaults.stringArray(forKey: SharedKeys.dismissedTrips) ?? []
        dismissed.append(trip.id)
        AppGroup.defaults.set(dismissed, forKey: SharedKeys.dismissedTrips)
        trips.removeAll { $0.id == trip.id }
    }

    private func homePoint() -> GeoPoint? {
        if let home = PinActions.savedPlaces().first(where: { TextNormalizer.key($0.name) == "home" }) {
            return home.center
        }
        return PinscapeSettings.lastKnownPoint
    }
}
