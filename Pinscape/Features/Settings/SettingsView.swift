import CoreLocation
import EventKit
import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationEngine.self) private var engine
    @Environment(ProStore.self) private var store
    @Query(sort: \Pin.createdAt, order: .reverse) private var allPins: [Pin]

    @State private var voiceConfirmation = PinscapeSettings.voiceConfirmation
    @State private var shakeToUndo = PinscapeSettings.shakeToUndo
    @State private var cooldown = PinscapeSettings.cooldownHours
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var paywall: PaywallReason?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    proCard
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section("Capture") {
                    Toggle(isOn: $voiceConfirmation) {
                        SettingLabel("Speak confirmation", detail: "“Got it. Tesco, batteries.”", symbol: "speaker.wave.2.fill", color: .pink)
                    }
                    Toggle(isOn: $shakeToUndo) {
                        SettingLabel("Shake to undo", detail: "Right after you drop a pin", symbol: "iphone.radiowaves.left.and.right", color: .orange)
                    }
                    NavigationLink {
                        ShortcutsHelpView()
                    } label: {
                        SettingLabel("Action Button & Back Tap", detail: "Capture without unlocking", symbol: "button.horizontal.top.press.fill", color: .indigo)
                    }
                }

                Section {
                    Picker(selection: $cooldown) {
                        Text("1 hour").tag(1.0)
                        Text("2 hours").tag(2.0)
                        Text("6 hours").tag(6.0)
                        Text("A day").tag(24.0)
                    } label: {
                        SettingLabel("Quiet after surfacing", detail: nil, symbol: "moon.zzz.fill", color: .purple)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("How long a pin stays quiet after it finds you, so popping in and out of a shop doesn't nag.")
                }

                Section("Permissions") {
                    PermissionRow(title: "Location", symbol: "location.fill", color: .blue, status: locationText, ok: engine.canSurfaceInBackground) {
                        engine.requestAccess()
                    }
                    PermissionRow(title: "Notifications", symbol: "bell.badge.fill", color: .red, status: notificationText, ok: notificationStatus == .authorized) {
                        Task {
                            if notificationStatus == .notDetermined {
                                await NotificationManager.requestAuthorization()
                                notificationStatus = await NotificationManager.authorizationStatus()
                            } else {
                                engine.openSettings()
                            }
                        }
                    }
                    PermissionRow(title: "Microphone & Speech", symbol: "mic.fill", color: .orange, status: SpeechCapture.isAuthorized ? "On, on-device" : "Off", ok: SpeechCapture.isAuthorized) {
                        Task {
                            if !SpeechCapture.hasBeenAsked {
                                _ = await SpeechCapture.requestPermissions()
                            } else {
                                engine.openSettings()
                            }
                        }
                    }
                    PermissionRow(title: "Calendar trips", symbol: "calendar", color: .teal, status: CalendarScout.shared.isAuthorized ? "On" : "Off", ok: CalendarScout.shared.isAuthorized) {
                        Task {
                            if CalendarScout.shared.status == .notDetermined {
                                _ = await CalendarScout.shared.requestAccess()
                            } else {
                                engine.openSettings()
                            }
                        }
                    }
                }

                Section {
                    PrivacyCard()
                } header: {
                    Text("Privacy")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section("Your data") {
                    if store.isPro {
                        ShareLink(item: exportText, subject: Text("Pinscape pins")) {
                            SettingLabel("Export to Notes", detail: "\(allPins.count) pins as text", symbol: "square.and.arrow.up", color: .yellow)
                        }
                    } else {
                        Button {
                            paywall = .export
                        } label: {
                            HStack {
                                SettingLabel("Export to Notes", detail: "Every pin as tidy text", symbol: "square.and.arrow.up", color: .yellow)
                                Spacer()
                                ProBadge()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        SettingLabel("Clear completed pins", detail: nil, symbol: "trash.fill", color: .red)
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Watching", value: "\(engine.regions.count) of 20 regions")
                } footer: {
                    Text("Pinscape · Leave thoughts in the real world.")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $paywall) { reason in
                PaywallView(reason: reason)
            }
            .confirmationDialog("Clear all completed pins?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    for pin in allPins where pin.isCompleted {
                        PinActions.delete(pin.id)
                    }
                }
            }
            .onChange(of: voiceConfirmation) { _, value in PinscapeSettings.voiceConfirmation = value }
            .onChange(of: shakeToUndo) { _, value in PinscapeSettings.shakeToUndo = value }
            .onChange(of: cooldown) { _, value in PinscapeSettings.cooldownHours = value }
            .task {
                notificationStatus = PinStore.isDemo ? .authorized : await NotificationManager.authorizationStatus()
            }
        }
    }

    private var proCard: some View {
        Button {
            if !store.isPro { paywall = .upgrade }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isPro ? "Pinscape Pro" : "Upgrade to Pro")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(store.isPro ? "Unlimited pins, groups and stickers. Thank you." : "Unlimited pins, place groups, NFC stickers, export.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if !store.isPro {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    private var locationText: String {
        switch engine.authorization {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While using — tap for Always"
        case .denied, .restricted: "Off"
        default: "Not set"
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        default: "Not set"
        }
    }

    private var exportText: String {
        var lines = ["Pinscape", ""]
        let grouped = Dictionary(grouping: allPins.filter { !$0.isCompleted }, by: \.placeName)
        for place in grouped.keys.sorted() {
            lines.append("📍 \(place)")
            for pin in grouped[place] ?? [] {
                lines.append("• \(pin.text)\(pin.isAmbient ? " (every visit)" : "")")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

struct SettingLabel: View {
    var title: String
    var detail: String?
    var symbol: String
    var color: Color

    init(_ title: String, detail: String?, symbol: String, color: Color) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PermissionRow: View {
    var title: String
    var symbol: String
    var color: Color
    var status: String
    var ok: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                SettingLabel(title, detail: status, symbol: symbol, color: color)
                Spacer()
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? .green : .orange)
            }
        }
        .foregroundStyle(.primary)
    }
}

/// What Pinscape does and doesn't do with your data, in plain words.
struct PrivacyCard: View {
    private let points: [(String, String)] = [
        ("waveform", "Voice is transcribed on your iPhone with Apple's on-device speech model."),
        ("lock.iphone", "Pins and places live in an encrypted on-device store. No account, no cloud, no sync."),
        ("location.slash", "No tracking. iOS tells Pinscape only that you arrived at a watched place."),
        ("eye.slash", "No analytics, no ads, no feeds. Nobody else ever sees a pin."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Private by design")
                    .font(.headline)
            }
            ForEach(points, id: \.0) { point in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: point.0)
                        .frame(width: 22)
                        .foregroundStyle(.secondary)
                    Text(point.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

/// How to put Pinscape on the Action Button, Back Tap and the Lock Screen.
struct ShortcutsHelpView: View {
    var body: some View {
        List {
            HelpStep(symbol: "button.horizontal.top.press.fill", color: .indigo, title: "Action Button", steps: [
                "Open Settings › Action Button.",
                "Swipe to Controls and choose Pinscape › Drop a Pin.",
                "Press and hold, say “Tesco, batteries”, let go of the thought.",
            ])
            HelpStep(symbol: "hand.tap.fill", color: .orange, title: "Back Tap", steps: [
                "Open Settings › Accessibility › Touch › Back Tap.",
                "Pick Double Tap, then Pinscape › Drop a Pin.",
            ])
            HelpStep(symbol: "lock.fill", color: .blue, title: "Lock Screen & Control Center", steps: [
                "Touch and hold the Lock Screen, tap Customise.",
                "Replace a bottom control with Drop a Pin, or add the Pinscape widget.",
                "In Control Center, tap + and add Drop a Pin.",
            ])
            HelpStep(symbol: "square.and.arrow.up.fill", color: .green, title: "Share Sheet", steps: [
                "Share a screenshot, link or text to Pinscape.",
                "It spots shops like Currys or IKEA and suggests the place.",
            ])
            HelpStep(symbol: "mic.fill", color: .pink, title: "Siri", steps: [
                "Say “Leave a thought with Pinscape”.",
                "Or “What's pinned here in Pinscape?” when you arrive.",
            ])
        }
        .navigationTitle("Capture anywhere")
    }
}

private struct HelpStep: View {
    var symbol: String
    var color: Color
    var title: String
    var steps: [String]

    var body: some View {
        Section {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(color.gradient, in: Circle())
                    Text(step)
                        .font(.subheadline)
                }
            }
        } header: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(color)
                .textCase(nil)
        }
    }
}
