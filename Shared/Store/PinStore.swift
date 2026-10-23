import Foundation
import SwiftData
import WidgetKit

/// The on-device database. Nothing here ever leaves the phone: no CloudKit, no sync, no analytics.
/// The store lives in the App Group container under iOS Data Protection, so it is encrypted at rest
/// and readable after first unlock, which lets a geofence wake Pinscape while the phone is locked.
enum PinStore {
    static let isDemo: Bool = ProcessInfo.processInfo.arguments.contains("-PinscapeDemo")
    /// Demo data as a Pro user, unless launched with `-PinscapeFree YES` to show the free tier.
    static let isDemoPro: Bool = isDemo && !ProcessInfo.processInfo.arguments.contains("-PinscapeFree")

    static let container: ModelContainer = makeContainer()

    @MainActor
    static var context: ModelContext { container.mainContext }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Pin.self, SavedPlace.self])
        if !isDemo {
            do {
                let directory = AppGroup.containerURL.appendingPathComponent("Pinscape", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                ])
                let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Pinscape.store"), cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                print("Pinscape: falling back to an in-memory store: \(error)")
            }
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("Pinscape could not create its store: \(error)")
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
}

/// Reads and writes pins from any process.
@MainActor
enum PinActions {
    static func activePins() -> [Pin] {
        activePins(in: PinStore.context)
    }

    static func activePins(in context: ModelContext) -> [Pin] {
        let descriptor = FetchDescriptor<Pin>(
            predicate: #Predicate<Pin> { $0.completedAt == nil },
            sortBy: [SortDescriptor(\Pin.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
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

    static func savedPlaces() -> [SavedPlace] {
        savedPlaces(in: PinStore.context)
    }

    static func savedPlaces(in context: ModelContext) -> [SavedPlace] {
        let descriptor = FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\SavedPlace.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Whether the free tier allows one more active pin.
    static var canAddPin: Bool {
        PinscapePlan.isPro || activePinCount() < PinscapePlan.freeActivePins
    }

    @discardableResult
    static func add(text: String, place: PlaceTarget, isAmbient: Bool, capturedByVoice: Bool, source: PinSource) -> Pin {
        let pin = Pin(text: text, place: place, isAmbient: isAmbient, capturedByVoice: capturedByVoice, source: source)
        PinStore.context.insert(pin)
        didChange()
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

    static func delete(_ id: UUID) {
        guard let pin = pin(id: id) else { return }
        PinStore.context.delete(pin)
        didChange()
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

    static func save() {
        try? PinStore.context.save()
    }

    /// Persists, refreshes widgets, and asks the app to re-plan geofences.
    static func didChange() {
        save()
        AppGroup.defaults.set(true, forKey: SharedKeys.needsReplan)
        WidgetCenter.shared.reloadAllTimelines()
        PinscapeHooks.pinsChanged?()
    }
}
