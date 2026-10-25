import Foundation
import UserNotifications

/// Local notifications only. Pinscape has no server and never sends a push.
@MainActor
enum NotificationManager {
    static let arrivalCategory = "PIN_ARRIVAL"
    static let doneAction = "PIN_DONE"
    static let laterAction = "PIN_LATER"
    static let tripCategory = "TRIP_NUDGE"

    /// Pinscape's own arrival chime (Resources/Sounds/Arrival.wav), or the iPhone's standard sound.
    static var arrivalSound: UNNotificationSound {
        PinscapeSettings.arrivalChime ? UNNotificationSound(named: UNNotificationSoundName("Arrival.wav")) : .default
    }

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
        content.sound = arrivalSound
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
            if let reason = await quietReason() {
                Diagnostics.record(.notificationQuiet, reason)
            }
        } catch {
            Diagnostics.record(.notificationFailed, error.localizedDescription)
        }
    }

    /// Why an arrival could come in without a sound, from what iOS reports, or nil if nothing
    /// Pinscape can see would silence it. (The ring switch and an active Focus aren't visible to apps.)
    static func quietReason() async -> String? {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral:
            break
        case .provisional:
            return "Pinscape's notifications are set to deliver quietly."
        default:
            return "Notifications are off for Pinscape."
        }
        if settings.soundSetting != .enabled {
            return "Sounds are off for Pinscape's notifications."
        }
        switch settings.timeSensitiveSetting {
        case .enabled:
            return nil
        case .notSupported:
            return "A Focus will silence arrivals unless Pinscape is one of its allowed apps."
        default:
            return "A Focus can silence arrivals: Time Sensitive is off for Pinscape."
        }
    }

    /// A sample arrival a few seconds from now: lock the iPhone to hear it as you would at a shop.
    static func postTestArrival(after delay: TimeInterval = 5) async {
        let content = UNMutableNotificationContent()
        content.title = "Pinscape"
        content.body = "This is how an arrival sounds."
        content.sound = arrivalSound
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-arrival", content: content, trigger: trigger))
        } catch {
            Diagnostics.record(.notificationFailed, "Test alert: \(error.localizedDescription)")
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
