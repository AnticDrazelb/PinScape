import Foundation
import Observation

/// The state behind the capture screen: what you said, where it should live, and saving it.
@MainActor
@Observable
final class CaptureModel {
    enum Stage: Equatable {
        case composing
        case saved
    }

    private var storedText: String
    var text: String {
        get { storedText }
        set {
            guard newValue != storedText else { return }
            storedText = newValue
            textChanged()
        }
    }

    private(set) var parsed: ParsedCapture
    /// Where the words point, once looked up.
    private(set) var resolvedPlace: PlaceTarget? = nil
    /// Where you picked by hand; wins over the parse.
    private(set) var chosenPlace: PlaceTarget? = nil
    /// Alternatives when a phrase was ambiguous ("Any Hobbycraft" vs one branch).
    private(set) var alternatives: [PlaceOption] = []
    /// "Home" said before Home was saved.
    private(set) var missingPlace: PlaceCategory? = nil
    private(set) var isResolving = false
    private(set) var suggestions: [PlaceSuggestion] = []
    private(set) var stage: Stage = .composing
    private(set) var usedVoice = false
    private(set) var savedPin: Pin? = nil
    private(set) var isAutoSaving = false

    private var storedAmbient = false
    /// Surface on every visit. Once you flip it, the words you say stop overriding it.
    var isAmbient: Bool {
        get { storedAmbient }
        set {
            storedAmbient = newValue
            ambientChosen = true
        }
    }

    let speech = SpeechCapture()
    let savedPlaces: [SavedPlace]

    @ObservationIgnored private var ambientChosen = false
    @ObservationIgnored private var resolveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var autoSaveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var lastPhrase: PlacePhrase? = nil
    private let source: PinSource

    static var market: Brand.Market {
        Locale.current.region?.identifier == "US" ? .us : .uk
    }

    init(request: CaptureRequest) {
        let places = PinActions.savedPlaces()
        savedPlaces = places
        source = request.source
        storedText = request.text
        chosenPlace = request.place
        parsed = CaptureParser(savedPlaceNames: places.map(\.name)).parse(request.text)
        speech.onFinish = { [weak self] transcript in
            self?.voiceFinished(transcript)
        }
        textChanged()
    }

    var place: PlaceTarget? { chosenPlace ?? resolvedPlace }

    var note: String { parsed.note }

    var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var canSave: Bool {
        stage == .composing && place != nil && !note.isEmpty
    }

    /// The words a place was heard as, for "Finding Bristol…".
    var heardPlace: String? { parsed.place?.text }

    var contextualStrings: [String] {
        savedPlaces.map(\.name) + BrandCatalog.all.map(\.name)
    }

    // MARK: Editing

    func choose(_ target: PlaceTarget) {
        cancelAutoSave()
        chosenPlace = target
        alternatives = []
        missingPlace = nil
    }

    func clearChosenPlace() {
        chosenPlace = nil
        textChanged()
    }

    func userInteracted() {
        cancelAutoSave()
    }

    private func textChanged() {
        parsed = CaptureParser(savedPlaceNames: savedPlaces.map(\.name)).parse(text)
        if !ambientChosen {
            storedAmbient = parsed.isAmbient
        }
        suggestions = parsed.place == nil && !parsed.note.isEmpty ? SmartSuggester.suggestions(for: parsed.note, market: Self.market) : []
        resolve()
    }

    private func resolve() {
        guard chosenPlace == nil else { return }
        guard let phrase = parsed.place else {
            resolveTask?.cancel()
            lastPhrase = nil
            resolvedPlace = nil
            alternatives = []
            missingPlace = nil
            isResolving = false
            return
        }
        guard phrase != lastPhrase else { return }
        lastPhrase = phrase
        resolveTask?.cancel()

        // Brands, kinds of place and your own places resolve instantly; the rest need a lookup.
        let instant: Bool
        switch phrase.match {
        case .brand, .category, .saved: instant = phrase.anchor == nil
        case .here, .downtown, .freeform: instant = false
        }
        isResolving = !instant
        let places = savedPlaces
        resolveTask = Task { [weak self] in
            if !instant {
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { return }
            }
            let outcome = await PlaceResolver.resolve(phrase, savedPlaces: places)
            if Task.isCancelled { return }
            self?.apply(outcome)
        }
    }

    private func apply(_ outcome: PlaceResolver.Outcome) {
        isResolving = false
        alternatives = []
        missingPlace = nil
        switch outcome {
        case .resolved(let target):
            resolvedPlace = target
        case .choose(let options):
            resolvedPlace = options.first?.target
            alternatives = options
        case .needsSavedPlace(let category):
            resolvedPlace = nil
            missingPlace = category
        case .notFound:
            resolvedPlace = nil
        }
    }

    // MARK: Voice

    func startListening() async -> Bool {
        cancelAutoSave()
        if !SpeechCapture.isAuthorized {
            guard !SpeechCapture.hasBeenAsked, await SpeechCapture.requestPermissions() else { return false }
        }
        speech.start(contextualStrings: contextualStrings)
        return speech.isListening
    }

    func transcriptChanged(_ transcript: String) {
        guard speech.isListening else { return }
        text = transcript
    }

    private func voiceFinished(_ transcript: String) {
        guard !transcript.isEmpty else { return }
        usedVoice = true
        text = transcript
        // Said it all? Save without a tap: capture in two seconds.
        autoSaveTask?.cancel()
        isAutoSaving = true
        autoSaveTask = Task { [weak self] in
            for _ in 0..<30 {
                guard let self, !Task.isCancelled else { return }
                if !self.isResolving { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            self.isAutoSaving = false
            if self.canSave {
                _ = self.save()
            }
        }
    }

    private func cancelAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        isAutoSaving = false
    }

    // MARK: Saving

    /// Returns false when the free tier is full.
    @discardableResult
    func save() -> Bool {
        cancelAutoSave()
        guard canSave, let place else { return true }
        guard PinActions.canAddPin else { return false }
        speech.cancel()
        let pin = PinActions.add(text: note, place: place, isAmbient: isAmbient, capturedByVoice: usedVoice, source: usedVoice ? .voice : source)
        savedPin = pin
        stage = .saved
        VoiceConfirmation.shared.say(SurfacingPolicy.confirmation(place: place.title, note: note))
        return true
    }
}
