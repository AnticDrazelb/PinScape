import AppIntents
import Foundation

/// "Hey Siri, leave a thought with Pinscape" → "What's the thought?" → "Where?"
struct QuickPinIntent: AppIntent {
    static let title: LocalizedStringResource = "Pin a Thought"
    static let description = IntentDescription("Leave a thought at a place. Pinscape surfaces it when you arrive.")

    @Parameter(title: "Thought", requestValueDialog: "What's the thought?")
    var note: String

    @Parameter(title: "Place", requestValueDialog: "Where should it find you?")
    var place: String

    static var parameterSummary: some ParameterSummary {
        Summary("Pin \(\.$note) at \(\.$place)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard PinActions.canAddPin else {
            let answer = "You've used all \(PinscapePlan.freeActivePins) free pins. Open Pinscape to go Pro or tick some off."
            return .result(dialog: "\(answer)")
        }
        let places = PinActions.savedPlaces()
        let parser = CaptureParser(savedPlaceNames: places.map(\.name))
        let phrase = parser.classify(place) ?? PlacePhrase(text: TextNormalizer.titleCase(place), spoken: place, match: .freeform, isNear: false)

        let text = CaptureParser.cleanNote(note)
        let target: PlaceTarget
        switch await PlaceResolver.resolve(phrase, savedPlaces: places) {
        case .resolved(let resolved):
            target = resolved
        case .choose(let options):
            // Never guess one of several places. "Any Hobbycraft" is a deliberate, broad choice and is
            // said back to you; several different places wait for you to pick in the app.
            if let any = options.first(where: { $0.target.kind == .search }) {
                target = any.target
            } else {
                Self.leaveForLater(note: text, place: phrase.spoken)
                let answer = "I found a few places called \(phrase.text). Open Pinscape to pick one; your note is waiting."
                return .result(dialog: "\(answer)")
            }
        case .needsSavedPlace(let category):
            let answer = "Pinscape doesn't know where \(category.displayName.lowercased()) is yet. Add it in Places first."
            return .result(dialog: "\(answer)")
        case .notFound:
            target = .search(phrase.text)
        }

        do {
            try PinActions.add(text: text, place: target, isAmbient: false, capturedByVoice: true, source: .siri)
        } catch {
            let answer = "Pinscape couldn't save that. Open the app to see why."
            return .result(dialog: "\(answer)")
        }
        ActionButtonTip.recordPinDropped()
        let place = target.kind == .search ? "any \(target.title)" : target.title
        return .result(dialog: "\(SurfacingPolicy.confirmation(place: place, note: text))")
    }

    /// Opens the capture screen with this note and place filled in, next time Pinscape comes forward.
    private static func leaveForLater(note: String, place: String) {
        var components = URLComponents()
        components.scheme = "pinscape"
        components.host = "capture"
        components.queryItems = [
            URLQueryItem(name: "place", value: place),
            URLQueryItem(name: "text", value: note),
            URLQueryItem(name: "source", value: PinSource.siri.rawValue),
        ]
        if let url = components.url {
            AppGroup.defaults.set(url.absoluteString, forKey: SharedKeys.pendingRoute)
        }
    }
}

/// "What's pinned here?"
struct PinsHereIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Pinned Here"
    static let description = IntentDescription("Hear the pins waiting at the place you're at.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let visits = VisitStore.current()
        let ids = Set(visits.flatMap(\.pinIDs))
        let pins = PinActions.activePins().filter { ids.contains($0.id) }
        if let visit = visits.last, !pins.isEmpty {
            let list = pins.map(\.text).joined(separator: ", ")
            let answer = "At \(visit.title): \(list)."
            return .result(dialog: "\(answer)")
        }
        let count = PinActions.activePinCount()
        let answer = count == 0 ? "Nothing pinned yet." : "Nothing here. You have \(count) \(count == 1 ? "pin" : "pins") waiting elsewhere."
        return .result(dialog: "\(answer)")
    }
}

/// Run from a Shortcuts "NFC tag" automation to show a sticker's pins.
struct OpenStickerIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Sticker Pins"
    static let description = IntentDescription("Shows the pins on one of your Pinscape NFC stickers.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Sticker name")
    var name: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let key = TextNormalizer.key(name)
        if let sticker = PinActions.savedPlaces().first(where: { $0.kind == .sticker && TextNormalizer.key($0.name) == key }) {
            AppModel.shared.open(URL(string: "pinscape://sticker/\(sticker.id.uuidString)")!)
        }
        return .result()
    }
}

struct PinscapeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCaptureIntent(),
            phrases: [
                "Drop a pin in \(.applicationName)",
                "New \(.applicationName) pin",
                "Open \(.applicationName) capture",
            ],
            shortTitle: "Drop a Pin",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: QuickPinIntent(),
            phrases: [
                "Leave a thought with \(.applicationName)",
                "Pin a thought in \(.applicationName)",
            ],
            shortTitle: "Pin a Thought",
            systemImageName: "text.bubble.fill"
        )
        AppShortcut(
            intent: PinsHereIntent(),
            phrases: [
                "What's pinned here in \(.applicationName)",
                "Read my \(.applicationName) pins",
            ],
            shortTitle: "Pins Here",
            systemImageName: "location.circle.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
