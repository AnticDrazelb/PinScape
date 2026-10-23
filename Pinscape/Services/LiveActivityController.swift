import ActivityKit
import Foundation
import UIKit

/// Starts the "you're here" checklist on the Lock Screen and Dynamic Island.
@MainActor
enum LiveActivityController {
    static func start(for visit: Visit, pins: [Pin]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !pins.isEmpty else { return }
        let items = pins.map { PinActivityAttributes.Item(id: $0.id, text: $0.text, done: $0.isCompleted) }
        let state = PinActivityAttributes.ContentState(items: items, arrivedAt: visit.arrivedAt)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(VisitStore.maximumLength))

        if let existing = Activity<PinActivityAttributes>.activities.first(where: { $0.attributes.placeKey == visit.regionID }) {
            await existing.update(content)
            return
        }
        let attributes = PinActivityAttributes(placeKey: visit.regionID, placeName: visit.title, symbol: visit.symbol, colorHex: visit.colorHex)
        do {
            _ = try Activity<PinActivityAttributes>.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            // iOS only allows starting an activity from the foreground; the notification still went
            // out, and the checklist starts when the app is opened. Only a foreground failure is news.
            if UIApplication.shared.applicationState == .active {
                Diagnostics.record(.liveActivityFailed, error.localizedDescription)
            }
        }
    }

    static func end(regionID: String) async {
        for activity in Activity<PinActivityAttributes>.activities where activity.attributes.placeKey == regionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Re-starts activities for places you're at when the app comes forward, since
    /// arrivals that happened in the background may not have been allowed to start one.
    static func resumeForCurrentVisits() async {
        for visit in VisitStore.current() {
            let pins = visit.pinIDs.compactMap { PinActions.pin(id: $0) }.filter { !$0.isCompleted }
            guard !pins.isEmpty else { continue }
            if Activity<PinActivityAttributes>.activities.contains(where: { $0.attributes.placeKey == visit.regionID }) { continue }
            await start(for: visit, pins: pins)
        }
    }
}
