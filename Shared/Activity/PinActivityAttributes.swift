import ActivityKit
import Foundation

/// The Live Activity shown while you're at a place with pins: a checklist on the Lock Screen
/// and in the Dynamic Island that you can tick off without unlocking.
struct PinActivityAttributes: ActivityAttributes {
    struct Item: Codable, Hashable, Identifiable {
        var id: UUID
        var text: String
        var done: Bool
    }

    struct ContentState: Codable, Hashable {
        var items: [Item]
        var arrivedAt: Date

        var remaining: Int { items.filter { !$0.done }.count }
    }

    var placeKey: String
    var placeName: String
    var symbol: String
    var colorHex: String
}

enum PinActivityUpdater {
    /// Ticks a pin on any Live Activity showing it; ends the activity once everything is done.
    static func toggle(_ id: UUID) async {
        #if !WIDGET_EXTENSION
        for activity in Activity<PinActivityAttributes>.activities {
            var state = activity.content.state
            guard let index = state.items.firstIndex(where: { $0.id == id }) else { continue }
            state.items[index].done.toggle()
            if state.remaining == 0 {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date.now.addingTimeInterval(3)))
            } else {
                await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
            }
        }
        #endif
    }
}
