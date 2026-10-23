import Foundation
import UserNotifications

/// Local notifications only. Pinscape has no server and never sends a push.
@MainActor
enum NotificationManager {
    static let arrivalCategory = "PIN_ARRIVAL"
    static let doneAction = "PIN_DONE"
    static let laterAction = "PIN_LATER"
    static let tripCategory = "TRIP_NUDGE"

    static func registerCategories() {
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let later = UNNotificationAction(identifier: laterAction, title: "Next visit", options: [], icon: UNNotificationActionIcon(systemImageName: "arrow.uturn.right.circle"))
        let arrival = UNNotificationCategory(identifier: arrivalCategory, actions: [done, later], intentIdentifiers: [], options: [])
        let trip = UNNotificationCategory(identifier: tripCategory, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([arrival, trip])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// "Tesco Express — Batteries"
    static func postArrival(visit: Visit, pins: [Pin]) async {
        let content = UNMutableNotificationContent()
        content.title = visit.title
        if pins.count == 1, let pin = pins.first {
            content.body = pin.text
            if pin.isAmbient { content.subtitle = "Every visit" }
        } else {
            content.subtitle = "\(pins.count) things you left here"
            content.body = pins.map { "• " + $0.text }.joined(separator: "\n")
        }
        content.sound = .default
        content.categoryIdentifier = arrivalCategory
        content.threadIdentifier = visit.placeKey
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.targetContentIdentifier = "place/\(visit.regionID)"
        content.userInfo = [
            "pinIDs": pins.map(\.id.uuidString),
            "regionID": visit.regionID,
        ]
        let request = UNNotificationRequest(identifier: "arrival.\(visit.regionID).\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil)
        let status = await authorizationStatus()
        if status != .authorized && status != .provisional && status != .ephemeral {
            // The arrival worked; the reminder can't be shown. Diagnostics says so plainly.
            Diagnostics.record(.notificationsOff, "Notification permission: \(status.rawValue)")
        }
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Diagnostics.record(.notificationFailed, error.localizedDescription)
        }
    }

    /// Handles a tap or an action button on an arrival notification.
    static func handle(action: String, pinIDs: [String], regionID: String?) {
        let ids = pinIDs.compactMap(UUID.init(uuidString:))
        switch action {
        case doneAction:
            for id in ids {
                PinActions.setCompleted(id, true)
            }
            Task {
                for id in ids {
                    await PinActivityUpdater.toggle(id)
                }
            }
        case laterAction:
            // Not now: quiet for this visit, back the next time you arrive.
            for id in ids {
                PinActions.rearm(id)
            }
        case UNNotificationDefaultActionIdentifier:
            AppModel.shared.showHereNow(regionID: regionID)
        default:
            break
        }
    }

    /// "You're going to Bristol tomorrow. Any pins to drop?"
    static func scheduleTripNudge(id: String, city: String, eventDate: Date) async {
        var scheduled = Set(AppGroup.defaults.stringArray(forKey: SharedKeys.scheduledTripNudges) ?? [])
        guard !scheduled.contains(id) else { return }
        let calendar = Calendar.current
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: eventDate)),
              let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: dayBefore),
              evening > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Off to \(city) tomorrow"
        content.body = "Anything you want to remember while you're there? Drop a pin."
        content.sound = .default
        content.categoryIdentifier = tripCategory
        content.userInfo = ["route": "capture", "place": city]
        let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: evening), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "trip.\(id)", content: content, trigger: trigger))
        scheduled.insert(id)
        AppGroup.defaults.set(Array(scheduled), forKey: SharedKeys.scheduledTripNudges)
    }
}
