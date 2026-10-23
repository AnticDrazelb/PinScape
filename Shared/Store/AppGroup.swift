import Foundation

/// The container the app, widgets and share extension all read and write.
enum AppGroup {
    static let identifier: String = (Bundle.main.object(forInfoDictionaryKey: "PinscapeAppGroup") as? String) ?? "group.com.pinscape.app"

    struct MissingContainer: LocalizedError {
        let identifier: String
        var errorDescription: String? {
            "The shared App Group “\(identifier)” isn't available, so the app and its extensions can't share pins. Check the App Groups capability and provisioning profile."
        }
    }

    /// The shared container directory, after checking the shared preferences too.
    ///
    /// A signed build without the App Group entitlement would otherwise give the app, widgets and
    /// share extension separate stores without anyone noticing, so in Release a missing container
    /// is an error: the store reports it and nothing is saved. Debug builds (unsigned CI, previews)
    /// fall back to the app's own sandbox.
    static func containerURL() throws -> URL {
        guard sharedDefaults != nil else { throw MissingContainer(identifier: identifier) }
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        #if DEBUG
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
        #else
        throw MissingContainer(identifier: identifier)
        #endif
    }

    /// Preferences shared by every Pinscape process.
    ///
    /// `UserDefaults(suiteName:)` only fails for a reserved name; a build missing the entitlement
    /// gets a private suite instead. Both are caught by `containerURL()`, which makes the store
    /// report the problem rather than letting the app and extensions quietly drift apart. The
    /// fallback only keeps a misconfigured build running long enough to say so.
    static let defaults: UserDefaults = sharedDefaults ?? .standard
    private static let sharedDefaults = UserDefaults(suiteName: identifier)
}

enum SharedKeys {
    static let isPro = "isPro"
    static let hasStickerPack = "hasStickerPack"
    static let proExpiresAt = "proExpiresAt"
    static let needsReplan = "needsReplan"
    static let pendingRoute = "pendingRoute"
    static let plannedRegions = "plannedRegions"
    static let currentVisits = "currentVisits"
    static let searchCache = "searchCache"
    static let voiceConfirmation = "voiceConfirmation"
    static let shakeToUndo = "shakeToUndo"
    static let everyVisitRestHours = "everyVisitRestHours"
    static let confirmationSound = "confirmationSound"
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

    /// The chime and haptic when a pin is dropped.
    static var confirmationSound: Bool {
        get { AppGroup.defaults.object(forKey: SharedKeys.confirmationSound) as? Bool ?? true }
        set { AppGroup.defaults.set(newValue, forKey: SharedKeys.confirmationSound) }
    }

    /// Hours an every-visit pin rests after surfacing.
    static var everyVisitRestHours: Double {
        get { AppGroup.defaults.object(forKey: SharedKeys.everyVisitRestHours) as? Double ?? SurfacingPolicy.defaultRest / 3600 }
        set { AppGroup.defaults.set(newValue, forKey: SharedKeys.everyVisitRestHours) }
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
        PinStore.isDemoPro || Entitlements.cachedIsPro
    }

    static var hasStickers: Bool {
        isPro || AppGroup.defaults.bool(forKey: SharedKeys.hasStickerPack)
    }
}
