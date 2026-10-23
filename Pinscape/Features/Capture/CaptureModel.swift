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

    enum SaveOutcome: Equatable {
        case saved
        /// The free tier is full.
        case needsPro
        /// Nothing was stored; `saveError` says why.
        case failed(String)
        /// No settled place or no thought yet.
        case notReady
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
    /// Set when saving failed. The pin was not stored.
    private(set) var saveError: String? = nil
    /// Auto-save found the free tier full; the screen hands over to the paywall.
    private(set) var hitPinLimit = false

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
    /// Bumped for every new place phrase, so a slow lookup can never overwrite a newer one.
    @ObservationIgnored private var resolveGeneration = 0
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

    /// Only a settled, unambiguous place can be saved: never the previous place while a new one
    /// is still being looked up, and never a guess among several matches.
    var canSave: Bool {
        guard stage == .composing, place != nil, !note.isEmpty else { return false }
        return chosenPlace != nil || !isResolving
    }

    /// Several places matched and you need to pick one.
    var needsChoice: Bool { place == nil && !alternatives.isEmpty }

    /// The words a place was heard as, for "Finding Bristol…".
    var heardPlace: String? { parsed.place?.text }

    var contextualStrings: [String] {
        savedPlaces.map(\.name) + BrandCatalog.all.map(\.name)
    }

    // MARK: Editing

    func choose(_ target: PlaceTarget) {
        cancelAutoSave()
        resolveGeneration += 1
        resolveTask?.cancel()
        isResolving = false
        chosenPlace = target
        alternatives = []
        missingPlace = nil
        saveError = nil
    }

    func userInteracted() {
        cancelAutoSave()
    }

    private func textChanged() {
        saveError = nil
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
            startResolution(for: nil)
            return
        }
        guard phrase != lastPhrase else { return }
        startResolution(for: phrase)
    }

    private func startResolution(for phrase: PlacePhrase?) {
        resolveGeneration += 1
        let generation = resolveGeneration
        resolveTask?.cancel()
        lastPhrase = phrase
        alternatives = []
        missingPlace = nil

        guard let phrase else {
            resolvedPlace = nil
            isResolving = false
            return
        }
        // Brands, kinds of place and your own places resolve on the spot.
        if let outcome = PlaceResolver.resolveInstantly(phrase, savedPlaces: savedPlaces) {
            isResolving = false
            apply(outcome)
            return
        }
        // Anything else needs Apple Maps. Drop the old place now so it can't be saved by mistake.
        resolvedPlace = nil
        isResolving = true
        let places = savedPlaces
        resolveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let outcome = await PlaceResolver.resolve(phrase, savedPlaces: places)
            guard let self, !Task.isCancelled, generation == self.resolveGeneration else { return }
            self.isResolving = false
            self.apply(outcome)
        }
    }

    /// Internal so tests can feed outcomes in directly.
    func apply(_ outcome: PlaceResolver.Outcome) {
        alternatives = []
        missingPlace = nil
        switch outcome {
        case .resolved(let target):
            resolvedPlace = target
        case .choose(let options):
            // Several matches: you pick. Nothing is chosen for you, by voice or otherwise.
            resolvedPlace = nil
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
            // Wait for a definite place. If it's still being looked up after a few seconds,
            // or several places matched, leave it for you to confirm rather than guess.
            for _ in 0..<40 {
                guard let self, !Task.isCancelled else { return }
                if !self.isResolving { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            self.isAutoSaving = false
            guard self.canSave else { return }
            if self.save() == .needsPro {
                self.hitPinLimit = true
            }
        }
    }

    private func cancelAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        isAutoSaving = false
    }

    // MARK: Saving

    /// Stores the pin. "Got it" (the chime, the haptic, the voice) only happens once it's safely on disk.
    @discardableResult
    func save() -> SaveOutcome {
        cancelAutoSave()
        guard canSave, let place else { return .notReady }
        guard PinActions.canAddPin else { return .needsPro }
        speech.cancel()
        do {
            let pin = try PinActions.add(text: note, place: place, isAmbient: isAmbient, capturedByVoice: usedVoice, source: usedVoice ? .voice : source)
            savedPin = pin
            saveError = nil
            stage = .saved
            CaptureFeedback.pinDropped()
            ActionButtonTip.recordPinDropped()
            VoiceConfirmation.shared.say(SurfacingPolicy.confirmation(place: place.title, note: note))
            return .saved
        } catch {
            let message = error.localizedDescription
            saveError = message
            CaptureFeedback.failed()
            return .failed(message)
        }
    }
}
