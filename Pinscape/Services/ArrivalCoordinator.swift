import Foundation
import WidgetKit

/// What happens when you walk into a place: the right pins surface on your Lock Screen.
@MainActor
enum ArrivalCoordinator {
    static func arrived(at region: PlannedRegion) async {
        let now = Date()
        let pins = PinActions.activePins()
        let rest = PinscapeSettings.everyVisitRestHours * 60 * 60
        let outcome = SurfacingPolicy.arrival(atRegionKey: region.candidate.key, pins: PinActions.snapshots(of: pins, places: PinActions.savedPlaces()), now: now, rest: rest)
        guard !outcome.surface.isEmpty else { return }
        let surfacing = Set(outcome.surface)
        let due = pins.filter { surfacing.contains($0.id) }

        for pin in due {
            pin.lastSurfacedAt = now
            pin.surfaceCount += 1
        }
        PinActions.save()
        Diagnostics.record(.arrival, "\(due.count) pin(s)")

        let visit = Visit(regionID: region.id, placeKey: region.candidate.key, title: region.candidate.title, subtitle: region.candidate.subtitle, symbol: region.candidate.symbol, colorHex: region.candidate.colorHex, arrivedAt: now, pinIDs: due.map(\.id))
        VisitStore.begin(visit)
        await NotificationManager.postArrival(visit: visit, pins: due)
        await LiveActivityController.start(for: visit, pins: due)
        WidgetCenter.shared.reloadAllTimelines()
        AppModel.shared.refreshVisits()

        if outcome.disarms {
            // Next-visit pins just disarmed. Release their places now, while iOS still has the app
            // awake, so the slots go to pins that are still waiting.
            AppGroup.defaults.set(true, forKey: SharedKeys.needsReplan)
            await LocationEngine.shared.replan()
        }
    }

    static func left(_ region: PlannedRegion) async {
        VisitStore.end(regionID: region.id)
        await LiveActivityController.end(regionID: region.id)
        AppModel.shared.refreshVisits()
    }
}
