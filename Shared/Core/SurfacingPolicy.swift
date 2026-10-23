import Foundation

/// Decides whether arriving somewhere should surface a pin right now.
///
/// A pin is either **next visit only** (the default) or **every visit**:
/// - Next visit only: surfaces the next time you arrive, then disarms. It stays in your list until
///   you tick it off, and you can re-arm it for another visit.
/// - Every visit: comes back each time you're there ("this bench = call dad"), resting in between
///   so popping in and out doesn't nag.
enum SurfacingPolicy {
    /// Ignore arrivals just after a pin is made — you're probably standing there.
    static let settleTime: TimeInterval = 3 * 60

    /// How long an every-visit pin rests after surfacing, unless you choose otherwise in Settings.
    static let defaultRest: TimeInterval = 6 * 60 * 60

    /// Whether a pin is still waiting to find you.
    static func isArmed(isAmbient: Bool, isCompleted: Bool, lastSurfacedAt: Date?) -> Bool {
        guard !isCompleted else { return false }
        return isAmbient || lastSurfacedAt == nil
    }

    static func shouldSurface(isAmbient: Bool, isCompleted: Bool, createdAt: Date, lastSurfacedAt: Date?, snoozedUntil: Date?, now: Date, rest: TimeInterval = defaultRest) -> Bool {
        guard isArmed(isAmbient: isAmbient, isCompleted: isCompleted, lastSurfacedAt: lastSurfacedAt) else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        if now.timeIntervalSince(createdAt) < settleTime { return false }
        if isAmbient, let lastSurfacedAt, now.timeIntervalSince(lastSurfacedAt) < rest { return false }
        return true
    }

    /// The words Pinscape says back after a capture: "Got it. Tesco, batteries."
    static func confirmation(place: String, note: String) -> String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return "Got it. \(place)." }
        let lowered = trimmedNote.prefix(1).lowercased() + trimmedNote.dropFirst()
        return "Got it. \(place), \(lowered)."
    }
}
