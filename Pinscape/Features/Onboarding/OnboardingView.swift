import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(LocationEngine.self) private var engine
    @State private var page = 0
    @State private var notificationsOn = false

    private let pageCount = 5

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    WelcomePage().tag(0)
                    SayItPage().tag(1)
                    FuzzyPage().tag(2)
                    ArrivePage().tag(3)
                    PermissionsPage(notificationsOn: $notificationsOn).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(index == page ? 0.95 : 0.3))
                            .frame(width: index == page ? 22 : 7, height: 7)
                    }
                }
                .animation(.snappy, value: page)
                .padding(.bottom, 22)

                Button {
                    if page < pageCount - 1 {
                        withAnimation(.smooth) { page += 1 }
                    } else {
                        app.finishOnboarding()
                    }
                } label: {
                    Text(page == pageCount - 1 ? "Start pinning" : "Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.gradient, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.45), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            notificationsOn = await NotificationManager.authorizationStatus() == .authorized
        }
    }
}

private struct OnboardingPage<Art: View>: View {
    var title: String
    var message: String
    @ViewBuilder var art: Art

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 20)
            art
                .frame(maxHeight: 340)
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 24)
    }
}

private struct WelcomePage: View {
    @State private var float = false

    var body: some View {
        OnboardingPage(title: "Leave thoughts in\nthe real world", message: "Say a thought and a place once. Pinscape brings it back when you're actually there. Stop remembering. Start arriving.") {
            ZStack {
                ForEach(0..<3) { ring in
                    Circle()
                        .stroke(.white.opacity(0.14 - Double(ring) * 0.04), lineWidth: 1)
                        .frame(width: 170 + CGFloat(ring) * 70, height: 170 + CGFloat(ring) * 70)
                }
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(Theme.gradient)
                    .frame(width: 132, height: 132)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 40, y: 14)
                    .overlay {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 62, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(y: float ? -6 : 6)
                orbit(symbol: "cart.fill", color: "#34C759", x: -118, y: -70)
                orbit(symbol: "hammer.fill", color: "#FF9500", x: 122, y: -40)
                orbit(symbol: "heart.fill", color: "#FF6FA8", x: -96, y: 96)
                orbit(symbol: "cup.and.saucer.fill", color: "#A2845E", x: 104, y: 92)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true }
            }
        }
    }

    private func orbit(symbol: String, color: String, x: CGFloat, y: CGFloat) -> some View {
        PlaceGlyph(symbol: symbol, colorHex: color, size: 46)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .offset(x: x, y: y + (float ? 4 : -4))
    }
}

private struct SayItPage: View {
    var body: some View {
        OnboardingPage(title: "Say it once", message: "Press the Action Button or tap the mic. Speak naturally. Pinscape works out the place and the thought, then says it back.") {
            VStack(spacing: 14) {
                bubble("“B&Q, wood stain — the dark one”", trailing: false)
                bubble("“Hay fever tablets at Boots”", trailing: true)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Got it. B&Q, wood stain.")
                        .font(.headline)
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassSurface(in: Capsule())
                .padding(.top, 8)
            }
        }
    }

    private func bubble(_ text: String, trailing: Bool) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
}

private struct FuzzyPage: View {
    private let chips: [(String, String, String)] = [
        ("Any Tesco", "cart.fill", "#34C759"),
        ("Near gym", "figure.strengthtraining.traditional", "#FF375F"),
        ("Downtown", "map.fill", "#14B8A6"),
        ("This bench", "mappin", "#FF5A4E"),
        ("Any pharmacy", "cross.case.fill", "#FF453A"),
        ("Mum's house", "heart.fill", "#FF6FA8"),
        ("IKEA", "sofa.fill", "#5E5CE6"),
        ("Bristol", "building.columns.fill", "#0EA5E9"),
    ]

    var body: some View {
        OnboardingPage(title: "Fuzzy places,\nnot addresses", message: "“Tesco” means any Tesco. “Near gym” means 400 m around it. No postcodes, no planning. Apple Maps does the rest.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(chips, id: \.0) { chip in
                    PlaceChip(title: chip.0, symbol: chip.1, colorHex: chip.2, selected: true)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct ArrivePage: View {
    var body: some View {
        OnboardingPage(title: "It finds you\nwhen you arrive", message: "Walk into any B&Q and it's on your Lock Screen. Tick things off from a Live Activity without unlocking.") {
            VStack(spacing: 12) {
                Text("09:41")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                HStack(alignment: .top, spacing: 12) {
                    PlaceGlyph(symbol: "hammer.fill", colorHex: "#FF9500", size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("B&Q")
                                .font(.headline)
                            Spacer()
                            Text("now")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Text("Wood stain — the dark one")
                            .font(.subheadline)
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
                .glassSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 6)
            }
        }
    }
}

private struct PermissionsPage: View {
    @Environment(LocationEngine.self) private var engine
    @Binding var notificationsOn: Bool

    var body: some View {
        OnboardingPage(title: "Private by design", message: "Voice is transcribed on your iPhone. Pins never leave it. iOS only tells Pinscape when you've arrived somewhere you pinned.") {
            VStack(spacing: 12) {
                PermissionButton(symbol: "location.fill", title: "Location", detail: "Choose “Always” so pins can find you", done: engine.canSurfaceInBackground) {
                    engine.requestAccess()
                }
                PermissionButton(symbol: "bell.badge.fill", title: "Notifications", detail: "How a pin says hello", done: notificationsOn) {
                    Task { notificationsOn = await NotificationManager.requestAuthorization() }
                }
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("No account. No cloud. No tracking.")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 6)
            }
        }
    }
}

private struct PermissionButton: View {
    var symbol: String
    var title: String
    var detail: String
    var done: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Theme.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(done ? .green : .white.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(.white)
            .padding(14)
            .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(done)
    }
}
