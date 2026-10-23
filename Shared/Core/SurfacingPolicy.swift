import Foundation

/// Decides whether arriving somewhere should surface a pin right now.
enum SurfacingPolicy {
    /// Ignore arrivals just after a pin is made — you're probably standing there.
    static let settleTime: TimeInterval = 3 * 60

    /// Default quiet period after a pin surfaces, so popping in and out of a shop doesn't nag.
    static let taskCooldown: TimeInterval = 2 * 60 * 60
    /// Ambient pins ("this bench = call dad") come back on later visits, not the same afternoon.
    static let ambientCooldown: TimeInterval = 6 * 60 * 60

    static func shouldSurface(isAmbient: Bool, isCompleted: Bool, createdAt: Date, lastSurfacedAt: Date?, snoozedUntil: Date?, now: Date, cooldown: TimeInterval? = nil) -> Bool {
        guard !isCompleted else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        if now.timeIntervalSince(createdAt) < settleTime { return false }
        if let lastSurfacedAt {
            let quiet = cooldown ?? (isAmbient ? ambientCooldown : taskCooldown)
            if now.timeIntervalSince(lastSurfacedAt) < quiet { return false }
        }
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
