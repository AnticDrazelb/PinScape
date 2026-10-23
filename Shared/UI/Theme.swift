import SwiftUI

extension Color {
    /// "#FF5A4E" or "FF5A4E".
    init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        let value = Scanner(string: string).scanUInt64(representation: .hexadecimal) ?? 0
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

enum Theme {
    /// Pinscape coral.
    static let accent = Color(hex: "#FF4F5A")
    static let ember = Color(hex: "#FF8A3D")
    static let rose = Color(hex: "#F0367E")
    static let dusk = Color(hex: "#5B3BE8")

    /// The sunset gradient on the icon, buttons and the capture orb.
    static let gradient = LinearGradient(colors: [ember, accent, rose], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func roundedTitle(_ style: Font.TextStyle = .largeTitle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// A place's round badge: a white symbol on its colour.
struct PlaceGlyph: View {
    var symbol: String
    var colorHex: String
    var size: CGFloat = 36

    init(symbol: String, colorHex: String, size: CGFloat = 36) {
        self.symbol = symbol
        self.colorHex = colorHex
        self.size = size
    }

    init(_ target: PlaceTarget, size: CGFloat = 36) {
        self.init(symbol: target.symbol, colorHex: target.colorHex, size: size)
    }

    var body: some View {
        let color = Color(hex: colorHex)
        ZStack {
            Circle()
                .fill(color.gradient)
            Circle()
                .strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, size / 48))
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A tappable place chip: glyph + name.
struct PlaceChip: View {
    var title: String
    var symbol: String
    var colorHex: String
    var selected = false

    var body: some View {
        HStack(spacing: 6) {
            PlaceGlyph(symbol: symbol, colorHex: colorHex, size: 22)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(selected ? Color(hex: colorHex).opacity(0.22) : Color.primary.opacity(0.07))
        }
        .overlay {
            Capsule()
                .strokeBorder(selected ? Color(hex: colorHex).opacity(0.7) : .clear, lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

/// "Next visit only" (the default) or "Every visit".
struct RemindModePicker: View {
    @Binding var isAmbient: Bool

    var body: some View {
        Picker("Remind me", selection: $isAmbient) {
            Text("Next visit only").tag(false)
            Text("Every visit").tag(true)
        }
        .pickerStyle(.segmented)
    }

    static func explanation(isAmbient: Bool, wasReminded: Bool = false) -> String {
        if isAmbient { return "Comes back each time you're there, like a note left on a bench." }
        if wasReminded { return "Already reminded you there. It waits in your list until you tick it off." }
        return "Reminds you the next time you arrive, then waits in your list."
    }
}
