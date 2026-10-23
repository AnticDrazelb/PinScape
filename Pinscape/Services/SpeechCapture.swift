import AVFoundation
import Foundation
import Observation
import Speech

/// Live dictation using Apple's on-device speech model. Audio never leaves the phone:
/// when on-device recognition is available Pinscape requires it.
@MainActor
@Observable
final class SpeechCapture {
    enum State: Equatable {
        case idle
        case listening
        case finished
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    /// 0...1 microphone level, for the orb.
    private(set) var level: Double = 0

    /// Called once with the final transcript when you stop talking.
    @ObservationIgnored var onFinish: ((String) -> Void)? = nil
    private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest? = nil
    @ObservationIgnored private var task: SFSpeechRecognitionTask? = nil
    @ObservationIgnored private var silenceWatch: Task<Void, Never>? = nil
    @ObservationIgnored private var lastHeard = Date()
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))

    var isListening: Bool { state == .listening }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioApplication.shared.recordPermission == .granted
    }

    static var hasBeenAsked: Bool {
        SFSpeechRecognizer.authorizationStatus() != .notDetermined && AVAudioApplication.shared.recordPermission != .undetermined
    }

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(contextualStrings: [String] = []) {
        guard state != .listening else { return }
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Dictation isn't available right now. Type instead.")
            return
        }
        transcript = ""
        level = 0

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.taskHint = .dictation
            request.contextualStrings = Array(contextualStrings.prefix(100))
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw CocoaError(.featureUnsupported)
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(for: request) { [weak self] level in
                Task { @MainActor in
                    self?.level = level
                }
            })
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isFinal, failed in
                Task { @MainActor in
                    self?.receive(text: text, isFinal: isFinal, failed: failed)
                }
            })
            state = .listening
            lastHeard = Date()
            watchForSilence()
        } catch {
            tearDown()
            state = .unavailable("The microphone isn't available. Type instead.")
        }
    }

    /// Stops listening and hands over what was heard.
    func finish() {
        guard state == .listening else { return }
        tearDown()
        state = .finished
        onFinish?(transcript)
    }

    /// Stops listening and throws the transcript away.
    func cancel() {
        task?.cancel()
        tearDown()
        state = .idle
    }

    private func receive(text: String?, isFinal: Bool, failed: Bool) {
        guard state == .listening else { return }
        if let text, text != transcript {
            transcript = text
            lastHeard = Date()
        }
        if isFinal {
            finish()
        } else if failed, transcript.isEmpty {
            tearDown()
            state = .unavailable("Didn't catch that. Try again or type.")
        }
    }

    /// Ends the capture after a pause, so speaking is all you have to do.
    private func watchForSilence() {
        silenceWatch?.cancel()
        silenceWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.state == .listening else { return }
                let quiet = Date().timeIntervalSince(self.lastHeard)
                if (!self.transcript.isEmpty && quiet > 1.6) || quiet > 8 {
                    self.finish()
                    return
                }
            }
        }
    }

    private func tearDown() {
        silenceWatch?.cancel()
        silenceWatch = nil
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Built outside the main actor: these run on audio and speech threads.

    nonisolated private static func tapBlock(for request: SFSpeechAudioBufferRecognitionRequest, onLevel: @escaping @Sendable (Double) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            onLevel(level(of: buffer))
        }
    }

    nonisolated private static func resultHandler(_ handler: @escaping @Sendable (String?, Bool, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in stride(from: 0, to: count, by: 4) {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(max(1, count / 4))).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        // -50 dB is silence, -10 dB is speaking up close.
        return Double(min(max((decibels + 50) / 40, 0), 1))
    }
}

/// Speaks the capture back: "Got it. Tesco, batteries."
@MainActor
final class VoiceConfirmation: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceConfirmation()

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        guard PinscapeSettings.voiceConfirmation, !PinStore.isDemo else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.04
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
