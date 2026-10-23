import Foundation
import WidgetKit

/// What happens when you walk into a place: the right pins surface on your Lock Screen.
@MainActor
enum ArrivalCoordinator {
    static func arrived(at region: PlannedRegion) async {
        let now = Date()
        let places = PinActions.savedPlaces()
        let rest = PinscapeSettings.everyVisitRestHours * 60 * 60
        let matching = PinActions.activePins().filter {
            PinActions.resolvedTarget(for: $0, places: places).matches(regionKey: region.candidate.key)
        }
        let due = matching.filter {
            SurfacingPolicy.shouldSurface(isAmbient: $0.isAmbient, isCompleted: $0.isCompleted, createdAt: $0.createdAt, lastSurfacedAt: $0.lastSurfacedAt, snoozedUntil: $0.snoozedUntil, now: now, rest: rest)
        }
        guard !due.isEmpty else { return }

        for pin in due {
            pin.lastSurfacedAt = now
            pin.surfaceCount += 1
        }
        PinActions.save()

        let visit = Visit(regionID: region.id, placeKey: region.candidate.key, title: region.candidate.title, subtitle: region.candidate.subtitle, symbol: region.candidate.symbol, colorHex: region.candidate.colorHex, arrivedAt: now, pinIDs: due.map(\.id))
        VisitStore.begin(visit)
        await NotificationManager.postArrival(visit: visit, pins: due)
        await LiveActivityController.start(for: visit, pins: due)
        WidgetCenter.shared.reloadAllTimelines()
        AppModel.shared.refreshVisits()
    }

    static func left(_ region: PlannedRegion) async {
        VisitStore.end(regionID: region.id)
        await LiveActivityController.end(regionID: region.id)
        AppModel.shared.refreshVisits()
    }
}
