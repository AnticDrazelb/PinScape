import Foundation

/// The container the app, widgets and share extension all read and write.
enum AppGroup {
    /// The group this build was made with.
    static let configuredIdentifier: String = (Bundle.main.object(forInfoDictionaryKey: "PinscapeAppGroup") as? String) ?? "group.com.pinscape.app"

    /// The App Group this install can really use: usually the one it was built with, but a
    /// sideloading tool re-signs with its own. AltStore and SideStore list theirs under
    /// `ALTAppGroups`; others only in the provisioning profile they embed. Nil when the install
    /// has no App Group at all, which some tools do.
    static let sharedIdentifier: String? = candidates().first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }

    /// Names the preferences suite too, which works (unshared) even without an App Group.
    static var identifier: String { sharedIdentifier ?? configuredIdentifier }

    /// Whether the app, widgets and Share Sheet can see the same pins in this install.
    static var isShared: Bool { sharedIdentifier != nil }

    static let isExtension: Bool = Bundle.main.bundleURL.pathExtension == "appex"

    private static func candidates() -> [String] {
        // An extension also looks at the app it's inside, two folders up.
        let app = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        let bundles = isExtension ? [Bundle.main, app].compactMap { $0 } : [Bundle.main]
        var identifiers = [configuredIdentifier]
        for bundle in bundles {
            identifiers += bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
            if let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"), let data = try? Data(contentsOf: url) {
                identifiers += ProvisioningProfile.appGroups(in: data)
            }
        }
        var seen = Set<String>()
        return identifiers.filter { seen.insert($0).inserted }
    }

    /// An extension in an install without an App Group can't reach the app's pins.
    struct NotShared: LocalizedError {
        var errorDescription: String? {
            "This copy of Pinscape was installed without an App Group, so the widgets and Share Sheet can't reach your pins. Add them in the app instead."
        }
    }

    struct BadSuiteName: LocalizedError {
        let identifier: String
        var errorDescription: String? {
            "Pinscape's shared settings “\(identifier)” can't be opened. This build is misconfigured."
        }
    }

    /// Where pins live.
    ///
    /// Normally the App Group container that the app, widgets and Share Sheet share. In an install
    /// without an App Group the app keeps pins in its own sandbox and Settings says sharing is
    /// off. Extensions can't reach that, so they refuse to save rather than start a second store
    /// that would drift from the app's.
    static func containerURL() throws -> URL {
        guard sharedDefaults != nil else { throw BadSuiteName(identifier: identifier) }
        if let sharedIdentifier, let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedIdentifier) {
            return url
        }
        #if !DEBUG
        if isExtension { throw NotShared() }
        #endif
        return try privateContainerURL()
    }

    /// The process's own Application Support folder: the app's store when there's no App Group.
    static func privateContainerURL() throws -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Preferences shared by every Pinscape process (or just the app's, without an App Group).
    ///
    /// `UserDefaults(suiteName:)` only fails for a reserved name, which `containerURL()` reports so
    /// the store refuses to open; the fallback only keeps such a build running long enough to say so.
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
