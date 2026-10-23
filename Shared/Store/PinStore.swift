import Foundation
import SwiftData
import WidgetKit

/// Whether pins can be read and written.
enum StoreHealth: Equatable {
    case ready
    /// Sample data for screenshots and previews; nothing is kept.
    case demo
    /// The on-device store couldn't be opened. Nothing can be saved until it can.
    case unavailable(String)
}

/// The on-device database. No CloudKit, no sync, no Pinscape server.
/// The store lives in the App Group container under iOS Data Protection, so it is encrypted at rest
/// and readable after first unlock, which lets a geofence wake Pinscape while the phone is locked.
enum PinStore {
    static let isDemo: Bool = ProcessInfo.processInfo.arguments.contains("-PinscapeDemo")
    /// Demo data as a Pro user, unless launched with `-PinscapeFree YES` to show the free tier.
    static let isDemoPro: Bool = isDemo && !ProcessInfo.processInfo.arguments.contains("-PinscapeFree")

    static let schema = Schema([Pin.self, SavedPlace.self])

    /// Replaced only by `openIfNeeded()`, on the main actor.
    private static var setup: (container: ModelContainer, health: StoreHealth) = makeContainer()

    static var container: ModelContainer { setup.container }
    static var health: StoreHealth { setup.health }

    /// Makes sure the store is open, trying again after a failed open: iOS may have woken Pinscape
    /// for an arrival before the phone's first unlock after a restart, while protected files were
    /// still unreadable. Returns whether pins can be read and written. When a retry succeeds the
    /// app is told, so it can refresh its screens, re-plan and catch up on missed arrivals.
    @MainActor
    @discardableResult
    static func openIfNeeded() -> Bool {
        guard case .unavailable = setup.health else { return true }
        setup = makeContainer()
        guard isWritable else { return false }
        PinscapeHooks.storeReopened?()
        return true
    }

    /// False when the store failed to open. Every write checks this, so a thought is never
    /// "saved" into memory that disappears when the app quits.
    static var isWritable: Bool {
        if case .unavailable = health { return false }
        return true
    }

    @MainActor
    static var context: ModelContext { container.mainContext }

    /// Opens (or creates) the persistent store at a location. Separate so tests can point it at a temporary file.
    static func openPersistentContainer(at url: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        ])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeContainer() -> (container: ModelContainer, health: StoreHealth) {
        if isDemo {
            return (emptyContainer(), .demo)
        }
        do {
            let url = storeURL(in: try AppGroup.containerURL())
            if AppGroup.isExtension {
                // Only the app creates the store, so a widget can't get there first with an empty
                // one and strand pins the app is about to move in.
                guard FileManager.default.fileExists(atPath: url.path) else { throw NotCreatedYet() }
            } else if AppGroup.isShared {
                // Pins kept while this app had no App Group (an earlier sideloaded install) move in.
                try adoptPrivateStore(from: storeURL(in: AppGroup.privateContainerURL()), to: url)
            }
            return (try openPersistentContainer(at: url), .ready)
        } catch {
            // Never quietly carry on with a throwaway store: the app shows what went wrong and
            // refuses to save, and the existing store file is left untouched for the next launch.
            Diagnostics.record(.storeUnavailable, error.localizedDescription)
            return (emptyContainer(), .unavailable(error.localizedDescription))
        }
    }

    struct NotCreatedYet: LocalizedError {
        var errorDescription: String? { "Open Pinscape once to set up your pins." }
    }

    static func storeURL(in container: URL) -> URL {
        container.appendingPathComponent("Pinscape", isDirectory: true).appendingPathComponent("Pinscape.store")
    }

    /// Moves a store into place if there's one at `source` and none at `destination` yet. Copies
    /// every file first and only then removes the originals, so a failure leaves the pins where
    /// they were (and the store reports it) rather than half-moved.
    static func adoptPrivateStore(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: source.path), !files.fileExists(atPath: destination.path) else { return }
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        ])
        let pairs = ["", "-shm", "-wal"]
            .map { (from: URL(fileURLWithPath: source.path + $0), to: URL(fileURLWithPath: destination.path + $0)) }
            .filter { files.fileExists(atPath: $0.from.path) }
        do {
            for pair in pairs {
                try files.copyItem(at: pair.from, to: pair.to)
            }
        } catch {
            for pair in pairs {
                try? files.removeItem(at: pair.to)
            }
            throw error
        }
        for pair in pairs {
            try? files.removeItem(at: pair.from)
        }
    }

    /// An empty in-memory container: demo data, or a read-only stand-in while the real store is unavailable.
    private static func emptyContainer() -> ModelContainer {
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("Pinscape could not create an in-memory store: \(error)")
        }
    }
}

/// Why a write didn't happen.
enum PersistenceError: LocalizedError {
    case storeUnavailable
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable: "Pinscape can't open your pins right now, so nothing was saved."
        case .saveFailed(let reason): "Pinscape couldn't save that: \(reason)"
        }
    }
}

/// Hooks the app installs so code shared with extensions can reach app-only services.
@MainActor
enum PinscapeHooks {
    /// Pins were added, edited or completed; geofences may need re-planning.
    static var pinsChanged: (@MainActor () -> Void)?
    /// Open a route in the app, e.g. "capture".
    static var openRoute: (@MainActor (String) -> Void)?
    /// A change couldn't be saved; the app tells you rather than pretending it worked.
    static var writeFailed: (@MainActor (String) -> Void)?
    /// The store opened after failing to; anything waiting on it can carry on.
    static var storeReopened: (@MainActor () -> Void)?
}

/// Reads and writes pins from any process.
@MainActor
enum PinActions {
    /// Active pins for display. A store that can't be read shows as empty; anything that acts on
    /// the answer (planning, arrivals) uses `fetchActivePins()`, which throws instead.
    static func activePins() -> [Pin] {
        (try? fetchActivePins(in: PinStore.context)) ?? []
    }

    /// Active pins, or an error if they can't be read, so a failure is never mistaken for "no pins".
    static func fetchActivePins() throws -> [Pin] {
        guard PinStore.isWritable else { throw PersistenceError.storeUnavailable }
        return try fetchActivePins(in: PinStore.context)
    }

    static func fetchActivePins(in context: ModelContext) throws -> [Pin] {
        let descriptor = FetchDescriptor<Pin>(
            predicate: #Predicate<Pin> { $0.completedAt == nil },
            sortBy: [SortDescriptor(\Pin.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    static func activePinCount() -> Int {
        activePinCount(in: PinStore.context)
    }

    static func activePinCount(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Pin>(predicate: #Predicate<Pin> { $0.completedAt == nil })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func pin(id: UUID) -> Pin? {
        pin(id: id, in: PinStore.context)
    }

    static func pin(id: UUID, in context: ModelContext) -> Pin? {
        var descriptor = FetchDescriptor<Pin>(predicate: #Predicate<Pin> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Saved places for display; see `activePins()`.
    static func savedPlaces() -> [SavedPlace] {
        (try? fetchSavedPlaces(in: PinStore.context)) ?? []
    }

    static func fetchSavedPlaces() throws -> [SavedPlace] {
        guard PinStore.isWritable else { throw PersistenceError.storeUnavailable }
        return try fetchSavedPlaces(in: PinStore.context)
    }

    static func fetchSavedPlaces(in context: ModelContext) throws -> [SavedPlace] {
        let descriptor = FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\SavedPlace.createdAt)])
        return try context.fetch(descriptor)
    }

    /// Whether the free tier allows one more active pin.
    static var canAddPin: Bool {
        PinscapePlan.isPro || activePinCount() < PinscapePlan.freeActivePins
    }

    /// Saves a new pin. Throws rather than returning a pin that only exists in memory.
    @discardableResult
    static func add(text: String, place: PlaceTarget, isAmbient: Bool, capturedByVoice: Bool, source: PinSource) throws -> Pin {
        guard PinStore.isWritable else { throw PersistenceError.storeUnavailable }
        let pin = Pin(text: text, place: place, isAmbient: isAmbient, capturedByVoice: capturedByVoice, source: source)
        PinStore.context.insert(pin)
        do {
            try commit()
        } catch {
            // Rolling back can leave the new pin in the context, where lists would show it and a
            // later save would write it. It wasn't saved, so take it out.
            if pin.modelContext != nil {
                PinStore.context.delete(pin)
            }
            throw error
        }
        afterChange()
        return pin
    }

    static func setCompleted(_ id: UUID, _ completed: Bool) {
        guard let pin = pin(id: id) else { return }
        pin.completedAt = completed ? Date() : nil
        didChange()
    }

    static func toggleCompleted(_ id: UUID) {
        guard let pin = pin(id: id) else { return }
        setCompleted(id, !pin.isCompleted)
    }

    /// Brings a reminded next-visit pin back for the next time you arrive.
    static func rearm(_ id: UUID) {
        guard let pin = pin(id: id) else { return }
        pin.lastSurfacedAt = nil
        // You may be standing there now; wait for a real next visit.
        pin.snoozedUntil = Date().addingTimeInterval(45 * 60)
        didChange()
    }

    static func delete(_ id: UUID) {
        guard let pin = pin(id: id) else { return }
        PinStore.context.delete(pin)
        didChange()
    }

    /// Database-free copies of pins for the planner and arrival logic.
    static func snapshots(of pins: [Pin], places: [SavedPlace]) -> [PinSnapshot] {
        pins.map { pin in
            PinSnapshot(id: pin.id, target: resolvedTarget(for: pin, places: places), isAmbient: pin.isAmbient, isCompleted: pin.isCompleted, createdAt: pin.createdAt, lastSurfacedAt: pin.lastSurfacedAt, snoozedUntil: pin.snoozedUntil)
        }
    }

    /// The place a pin points at, with a saved place's latest position and size.
    static func resolvedTarget(for pin: Pin, places: [SavedPlace]) -> PlaceTarget {
        var target = pin.place
        guard let id = target.savedPlaceID, let place = places.first(where: { $0.id == id }) else { return target }
        switch target.kind {
        case .saved:
            target = place.target(near: target.isNear)
        case .group:
            target.members = place.members
            target.name = place.name
        default:
            break
        }
        return target
    }

    /// Writes pending changes, or rolls them back and throws.
    static func commit() throws {
        guard PinStore.isWritable else {
            PinStore.context.rollback()
            throw PersistenceError.storeUnavailable
        }
        do {
            try PinStore.context.save()
        } catch {
            PinStore.context.rollback()
            Diagnostics.record(.saveFailed, error.localizedDescription)
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }

    /// Saves, reporting a failure to the app instead of swallowing it. Returns whether it was saved.
    @discardableResult
    static func save() -> Bool {
        do {
            try commit()
            return true
        } catch {
            PinscapeHooks.writeFailed?(error.localizedDescription)
            return false
        }
    }

    /// Saves, then refreshes widgets and asks the app to re-plan geofences.
    @discardableResult
    static func didChange() -> Bool {
        let saved = save()
        afterChange()
        return saved
    }

    /// Everything that depends on pins: widgets and the geofence plan.
    static func afterChange() {
        AppGroup.defaults.set(true, forKey: SharedKeys.needsReplan)
        WidgetCenter.shared.reloadAllTimelines()
        PinscapeHooks.pinsChanged?()
    }
}
