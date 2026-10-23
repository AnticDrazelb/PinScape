import Foundation
import SwiftData
import WidgetKit

/// What happens when you walk into a place: the right pins surface on your Lock Screen.
///
/// That the pins surfaced is saved before anything is shown, so a reminder you saw is always
/// recorded and can't come round again. If it can't be saved (the store is still locked after a
/// restart, or a write fails) nothing is shown yet: the arrival is tried twice more over a few
/// seconds, then kept until the store recovers, for as long as you're still there.
@MainActor
enum ArrivalCoordinator {
    private struct Arrival {
        var regionID: String
        /// Nil when iOS reported the arrival before the plan could be read (before first unlock).
        var region: PlannedRegion?
        var date: Date
    }

    /// Arrivals not recorded yet, by region. Kept in memory: they only matter while you're there,
    /// and leaving (or two hours passing) drops them.
    private static var pending: [String: Arrival] = [:]
    static let pendingLifetime: TimeInterval = 2 * 60 * 60

    static func arrived(at region: PlannedRegion) async {
        await process(Arrival(regionID: region.id, region: region, date: Date()), attempts: 3)
    }

    /// iOS reported an arrival at a region Pinscape can't look up yet because its files are still
    /// protected. It's handled once the store opens.
    static func arrived(atUnreadableRegion id: String) {
        pending[id] = Arrival(regionID: id, region: nil, date: Date())
        Diagnostics.record(.arrivalDeferred, "Pins are locked until the iPhone is unlocked")
    }

    static func left(regionID: String) async {
        pending[regionID] = nil
        VisitStore.end(regionID: regionID)
        await LiveActivityController.end(regionID: regionID)
        AppModel.shared.refreshVisits()
    }

    /// Tries arrivals that couldn't be recorded earlier: when the store opens, or the app comes forward.
    static func retryPending() async {
        let waiting = pending.values.sorted { $0.date < $1.date }
        pending = [:]
        for arrival in waiting where Date().timeIntervalSince(arrival.date) < pendingLifetime {
            await process(arrival, attempts: 1)
        }
    }

    private static func process(_ arrival: Arrival, attempts: Int) async {
        var failure = ""
        for attempt in 0..<attempts {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(attempt))
            }
            do {
                guard PinStore.openIfNeeded() else { throw PersistenceError.storeUnavailable }
                // A region that's no longer planned has nothing left to surface.
                guard let region = arrival.region ?? RegionStore.load().first(where: { $0.id == arrival.regionID }) else { return }
                let recorded = try record(arrivalAt: region, now: Date(), in: PinStore.context, rest: PinscapeSettings.everyVisitRestHours * 60 * 60)
                if !recorded.pins.isEmpty {
                    await announce(recorded, at: region, arrivedAt: arrival.date)
                }
                return
            } catch {
                failure = error.localizedDescription
            }
        }
        pending[arrival.regionID] = arrival
        Diagnostics.record(.arrivalDeferred, "\(failure) Will try again while you're there.")
    }

    struct RecordedArrival {
        var pins: [Pin]
        /// Some were next-visit pins, now disarmed, so the plan can release their places.
        var disarms: Bool
    }

    /// Marks the pins due at a region as surfaced and saves that. If the pins can't be read or the
    /// save fails it throws, with the change rolled back so the pins are still due next time, and
    /// nothing should be shown.
    static func record(arrivalAt region: PlannedRegion, now: Date, in context: ModelContext, rest: TimeInterval, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> RecordedArrival {
        let pins = try PinActions.fetchActivePins(in: context)
        let places = try PinActions.fetchSavedPlaces(in: context)
        let outcome = SurfacingPolicy.arrival(atRegionKey: region.candidate.key, pins: PinActions.snapshots(of: pins, places: places), now: now, rest: rest)
        let surfacing = Set(outcome.surface)
        let due = pins.filter { surfacing.contains($0.id) }
        guard !due.isEmpty else { return RecordedArrival(pins: [], disarms: false) }

        for pin in due {
            pin.lastSurfacedAt = now
            pin.surfaceCount += 1
        }
        do {
            try save(context)
        } catch {
            context.rollback()
            Diagnostics.record(.saveFailed, "Arrival: \(error.localizedDescription)")
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
        return RecordedArrival(pins: due, disarms: outcome.disarms)
    }

    private static func announce(_ recorded: RecordedArrival, at region: PlannedRegion, arrivedAt: Date) async {
        Diagnostics.record(.arrival, "\(recorded.pins.count) pin(s)")
        let candidate = region.candidate
        let visit = Visit(regionID: region.id, placeKey: candidate.key, title: candidate.title, subtitle: candidate.subtitle, symbol: candidate.symbol, colorHex: candidate.colorHex, arrivedAt: arrivedAt, pinIDs: recorded.pins.map(\.id))
        VisitStore.begin(visit)
        await NotificationManager.postArrival(visit: visit, pins: recorded.pins)
        await LiveActivityController.start(for: visit, pins: recorded.pins)
        WidgetCenter.shared.reloadAllTimelines()
        AppModel.shared.refreshVisits()

        if recorded.disarms {
            // Next-visit pins just disarmed. Release their places now, while iOS still has the app
            // awake, so the slots go to pins that are still waiting.
            AppGroup.defaults.set(true, forKey: SharedKeys.needsReplan)
            await LocationEngine.shared.replan()
        }
    }
}
