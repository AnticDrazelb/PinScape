import Foundation
import Observation
import SwiftUI

/// What the capture screen should start with.
struct CaptureRequest: Identifiable, Equatable {
    let id = UUID()
    var text: String = ""
    var place: PlaceTarget? = nil
    var listen: Bool = true
    var source: PinSource = .app
}

/// "Pinned to Tesco · Shake to undo"
struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    var pinID: UUID
    var place: String
    var note: String
    var createdAt = Date()
}

enum PaywallReason: String, Identifiable {
    case pinLimit, placeLimit, groups, stickers, export, upgrade
    var id: String { rawValue }

    var headline: String {
        switch self {
        case .pinLimit: "You've filled your \(PinscapePlan.freeActivePins) free pins"
        case .placeLimit: "Save every place that matters"
        case .groups: "Group places together"
        case .stickers: "Pins for the pantry door"
        case .export: "Take your pins anywhere"
        case .upgrade: "Your memory, location-aware"
        }
    }
}

/// App-wide navigation and transient state.
@MainActor
@Observable
final class AppModel {
    enum Sheet: Identifiable, Equatable {
        case pin(UUID)
        case places
        case settings
        case paywall(PaywallReason)
        case hereNow
        case sticker(UUID)
        case map
        case captureHelp

        var id: String {
            switch self {
            case .pin(let id): "pin-\(id)"
            case .places: "places"
            case .settings: "settings"
            case .paywall(let reason): "paywall-\(reason.rawValue)"
            case .hereNow: "here"
            case .sticker(let id): "sticker-\(id)"
            case .map: "map"
            case .captureHelp: "capture-help"
            }
        }
    }

    static let shared = AppModel()

    var capture: CaptureRequest? = nil
    var sheet: Sheet? = nil
    var undo: UndoToast? = nil
    /// A change that couldn't be saved, shown as an alert.
    var storeAlert: String? = nil
    /// Bumped when the store is reopened, so every view rebuilds against it.
    private(set) var storeGeneration = 0
    private(set) var storeHealth: StoreHealth = PinStore.health
    var showOnboarding: Bool
    private(set) var visits: [Visit] = []

    @ObservationIgnored private var undoTimer: Task<Void, Never>? = nil
    private init() {
        showOnboarding = !AppGroup.defaults.bool(forKey: SharedKeys.hasOnboarded) && !PinStore.isDemo
        visits = VisitStore.current()
    }

    // MARK: Capture

    func startCapture(text: String = "", place: PlaceTarget? = nil, listen: Bool = true, source: PinSource = .app) {
        guard PinStore.isWritable else {
            storeAlert = PersistenceError.storeUnavailable.localizedDescription
            return
        }
        guard PinActions.canAddPin else {
            sheet = .paywall(.pinLimit)
            return
        }
        sheet = nil
        capture = CaptureRequest(text: text, place: place, listen: listen, source: source)
    }

    func didCapture(_ pin: Pin) {
        undo = UndoToast(pinID: pin.id, place: pin.placeName, note: pin.text)
        undoTimer?.cancel()
        undoTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.undo = nil }
        }
    }

    /// Shake to undo: removes the pin you just dropped.
    func undoLastCapture() {
        guard let undo, Date().timeIntervalSince(undo.createdAt) < 10 else { return }
        PinActions.delete(undo.pinID)
        CaptureFeedback.undone()
        withAnimation(.snappy) { self.undo = nil }
        VoiceConfirmation.shared.say("Undone.")
    }

    // MARK: Routing

    func open(_ url: URL) {
        guard url.scheme == "pinscape" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host {
        case "capture":
            let text = query.first { $0.name == "text" }?.value ?? ""
            let place = query.first { $0.name == "place" }?.value
            let source = query.first { $0.name == "source" }?.value.flatMap(PinSource.init(rawValue:)) ?? .widget
            startCapture(text: place.map { "\($0), \(text)" } ?? text, listen: text.isEmpty && place == nil, source: source)
        case "pin":
            if let id = parts.first.flatMap(UUID.init(uuidString:)) { sheet = .pin(id) }
        case "sticker":
            if let id = parts.first.flatMap(UUID.init(uuidString:)) { sheet = .sticker(id) }
        case "here":
            sheet = .hereNow
        case "places":
            sheet = .places
        case "paywall":
            sheet = .paywall(.upgrade)
        default:
            break
        }
    }

    func open(route: String) {
        if let url = URL(string: route.contains("://") ? route : "pinscape://\(route)") {
            open(url)
        }
    }

    /// Picks up a route left by an intent that ran before the UI was ready.
    func handlePendingRoute() {
        guard let route = AppGroup.defaults.string(forKey: SharedKeys.pendingRoute) else { return }
        AppGroup.defaults.removeObject(forKey: SharedKeys.pendingRoute)
        open(route: route)
    }

    /// Retries a store that failed to open: when the app comes forward, at the first unlock after a
    /// restart, and from the problem screen. Success arrives through `storeDidReopen()`.
    func reopenStoreIfNeeded() {
        PinStore.openIfNeeded()
        storeHealth = PinStore.health
    }

    /// The store opened after failing to, wherever that was noticed: here, a background re-plan or
    /// an arrival. Refresh the screens, put the watched places right and catch up on arrivals.
    func storeDidReopen() {
        Diagnostics.record(.storeReopened)
        storeGeneration += 1
        storeHealth = PinStore.health
        if !LocationEngine.shared.isPlanning {
            LocationEngine.shared.scheduleReplan()
        }
        Task { await ArrivalCoordinator.retryPending() }
    }

    func refreshVisits() {
        visits = VisitStore.current()
    }

    func showHereNow(regionID: String?) {
        refreshVisits()
        sheet = .hereNow
        Task { await LiveActivityController.resumeForCurrentVisits() }
    }

    func finishOnboarding() {
        AppGroup.defaults.set(true, forKey: SharedKeys.hasOnboarded)
        showOnboarding = false
    }
}
