import AudioToolbox
import CoreHaptics
import UIKit

/// The "it landed" moment after a capture: a two-beat haptic and a short chime,
/// so a pin dropped with the Action Button can be felt and heard without looking.
/// The chime is a system sound, so it follows the Ring/Silent switch.
@MainActor
enum CaptureFeedback {
    private static var soundID: SystemSoundID = 0
    private static var engine: CHHapticEngine?

    /// Loads the sound and warms up the haptic engine so the first drop isn't late.
    static func prepare() {
        if soundID == 0, let url = Bundle.main.url(forResource: "PinDrop", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        }
        if engine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            engine = try? CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.playsHapticsOnly = true
        }
    }

    static func pinDropped() {
        guard PinscapeSettings.confirmationSound else { return }
        prepare()
        playHaptic()
        if soundID != 0 {
            AudioServicesPlaySystemSound(soundID)
        }
    }

    static func undone() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// A sharp tick as the pin goes in, then a softer landing.
    private static func playHaptic() {
        guard let engine else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        do {
            let tick = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9),
            ], relativeTime: 0)
            let landing = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
            ], relativeTime: 0.085)
            let pattern = try CHHapticPattern(events: [tick, landing], parameters: [])
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
