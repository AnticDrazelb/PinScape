import Foundation

/// The container the app, widgets and share extension all read and write.
enum AppGroup {
    static let identifier: String = (Bundle.main.object(forInfoDictionaryKey: "PinscapeAppGroup") as? String) ?? "group.com.pinscape.app"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        // Unsigned builds (CI, previews) have no group container; keep working from the app's own sandbox.
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}

enum SharedKeys {
    static let isPro = "isPro"
    static let hasStickerPack = "hasStickerPack"
    static let needsReplan = "needsReplan"
    static let pendingRoute = "pendingRoute"
    static let plannedRegions = "plannedRegions"
    static let currentVisits = "currentVisits"
    static let searchCache = "searchCache"
    static let voiceConfirmation = "voiceConfirmation"
    static let shakeToUndo = "shakeToUndo"
    static let cooldownHours = "cooldownHours"
    static let hasOnboarded = "hasOnboarded"
    static let lastLatitude = "lastLatitude"
    static let lastLongitude = "lastLongitude"
    static let scheduledTripNudges = "scheduledTripNudges"
    static let dismissedTrips = "dismissedTrips"
}

/// Settings shared by every Pinscape process.
enum PinscapeSettings {
    static var voiceConfirmation: Bool {
        get { AppGroup.defaults.object(forKey: SharedKeys.voiceConfirmation) as? Bool ?? true }
        set { AppGroup.defaults.set(newValue, forKey: SharedKeys.voiceConfirmation) }
    }

    static var shakeToUndo: Bool {
        get { AppGroup.defaults.object(forKey: SharedKeys.shakeToUndo) as? Bool ?? true }
        set { AppGroup.defaults.set(newValue, forKey: SharedKeys.shakeToUndo) }
    }

    /// Hours before the same pin can surface again.
    static var cooldownHours: Double {
        get { AppGroup.defaults.object(forKey: SharedKeys.cooldownHours) as? Double ?? 2 }
        set { AppGroup.defaults.set(newValue, forKey: SharedKeys.cooldownHours) }
    }

    /// Last known position, kept so extensions can rank places without asking for location.
    static var lastKnownPoint: GeoPoint? {
        get {
            guard let lat = AppGroup.defaults.object(forKey: SharedKeys.lastLatitude) as? Double,
                  let lon = AppGroup.defaults.object(forKey: SharedKeys.lastLongitude) as? Double else { return nil }
            return GeoPoint(latitude: lat, longitude: lon)
        }
        set {
            AppGroup.defaults.set(newValue?.latitude, forKey: SharedKeys.lastLatitude)
            AppGroup.defaults.set(newValue?.longitude, forKey: SharedKeys.lastLongitude)
        }
    }
}

/// What the free tier includes.
enum PinscapePlan {
    static let freeActivePins = 10
    static let freeSavedPlaces = 1

    static var isPro: Bool {
        AppGroup.defaults.bool(forKey: SharedKeys.isPro) || PinStore.isDemoPro
    }

    static var hasStickers: Bool {
        isPro || AppGroup.defaults.bool(forKey: SharedKeys.hasStickerPack)
    }
}
