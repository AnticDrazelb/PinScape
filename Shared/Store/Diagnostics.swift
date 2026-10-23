import Foundation
import os

/// A small, privacy-conscious record of what went wrong and when, shown in Settings › Diagnostics
/// to answer "why didn't it remind me?". It never stores what you wrote or where you were.
enum Diagnostics {
    enum Event: String, Codable {
        case storeUnavailable
        case saveFailed
        case monitorStopped
        case monitorRestarted
        case searchFailed
        case planApplied
        case planIncomplete
        case arrival
        case notificationFailed
        case notificationsOff
        case liveActivityFailed

        var title: String {
            switch self {
            case .storeUnavailable: "Couldn't open pins"
            case .saveFailed: "Couldn't save"
            case .monitorStopped: "Location monitoring stopped"
            case .monitorRestarted: "Location monitoring restarted"
            case .searchFailed: "Apple Maps search failed"
            case .planApplied: "Places armed"
            case .planIncomplete: "Some places couldn't be armed"
            case .arrival: "Arrived at a pinned place"
            case .notificationFailed: "Notification failed"
            case .notificationsOff: "Arrived, but notifications are off"
            case .liveActivityFailed: "Live Activity didn't start"
            }
        }

        var isProblem: Bool {
            switch self {
            case .planApplied, .arrival, .monitorRestarted: false
            default: true
            }
        }
    }

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var event: Event
        var detail: String
    }

    private static let key = "diagnostics"
    private static let limit = 60
    static let logger = Logger(subsystem: "com.pinscape", category: "pinscape")

    /// - Parameter detail: a short technical note. Never pass pin text or coordinates.
    static func record(_ event: Event, _ detail: String = "") {
        if event.isProblem {
            logger.error("\(event.rawValue, privacy: .public): \(detail, privacy: .private)")
        } else {
            logger.info("\(event.rawValue, privacy: .public): \(detail, privacy: .private)")
        }
        var entries = recent()
        entries.insert(Entry(date: Date(), event: event, detail: detail), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        AppGroup.defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }

    static func recent() -> [Entry] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }
}
