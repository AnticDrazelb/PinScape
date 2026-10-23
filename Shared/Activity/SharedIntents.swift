import AppIntents
import Foundation

/// Opens Pinscape listening. Powers the Action Button, Control Center, Lock Screen control and widgets.
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Drop a Pin"
    static let description = IntentDescription("Open Pinscape listening, ready to leave a thought at a place.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        AppGroup.defaults.set("capture", forKey: SharedKeys.pendingRoute)
        PinscapeHooks.openRoute?("capture")
        return .result()
    }
}

/// Ticks a pin off from a widget or the Live Activity without opening the app.
struct CompletePinIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Pin"
    static let description = IntentDescription("Marks a pin as done.")
    static let isDiscoverable: Bool = false

    @Parameter(title: "Pin")
    var pinID: String

    init() {}

    init(pinID: UUID) {
        self.pinID = pinID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: pinID) else { return .result() }
        PinActions.toggleCompleted(id)
        await PinActivityUpdater.toggle(id)
        return .result()
    }
}
