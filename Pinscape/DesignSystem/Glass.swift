import SwiftUI

extension View {
    /// Liquid Glass on iOS 26, frosted material before it.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.glass(interactive: interactive, tint: tint), in: shape)
        } else {
            self
                .background {
                    ZStack {
                        shape.fill(.regularMaterial)
                        if let tint {
                            shape.fill(tint.opacity(0.18))
                        }
                    }
                }
                .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
    }

    @available(iOS 26.0, *)
    private static func glass(interactive: Bool, tint: Color?) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        return interactive ? glass.interactive() : glass
    }

    /// The bold call to action: glass prominent on iOS 26, filled before it.
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// A quieter button: glass on iOS 26, bordered before it.
    @ViewBuilder
    func secondaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// The soft card used for rows and banners on the home screen.
    func cardBackground(cornerRadius: CGFloat = 22) -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A slowly drifting mesh of Pinscape colours, used behind capture and onboarding.
struct AuroraBackground: View {
    var colors: [Color] = [
        Color(hex: "#160B2E"), Color(hex: "#2B124C"), Color(hex: "#150A26"),
        Color(hex: "#5B2A86"), Color(hex: "#FF4F5A"), Color(hex: "#3A1A6E"),
        Color(hex: "#1A0D33"), Color(hex: "#FF8A3D"), Color(hex: "#2A0F3F"),
    ]
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let drift = Float(sin(t * 0.35)) * 0.08
            let sway = Float(cos(t * 0.27)) * 0.08
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + drift, 0.55 + sway], [1, 0.5],
                    [0, 1], [0.5 - sway, 1], [1, 1],
                ],
                colors: colors
            )
        }
        .ignoresSafeArea()
    }
}

/// A small rounded label: "Every visit", "Voice".
struct Badge: View {
    var text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

extension Double {
    /// "Nearby", "350 m", "1.2 km" — or feet and miles where people use them.
    var distanceText: String {
        if self < 40 { return "Nearby" }
        if Locale.current.measurementSystem == .us {
            let feet = self * 3.28084
            if feet < 1_000 { return "\(Int((feet / 50).rounded() * 50)) ft" }
            return String(format: "%.1f mi", self / 1_609.34)
        }
        if self < 1_000 { return "\(Int((self / 10).rounded() * 10)) m" }
        return String(format: "%.1f km", self / 1_000)
    }
}
