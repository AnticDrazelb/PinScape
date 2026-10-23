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
    @State private var confirmationSound = PinscapeSettings.confirmationSound
    @State private var restHours = PinscapeSettings.everyVisitRestHours
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
                    Toggle(isOn: $confirmationSound) {
                        SettingLabel("Haptic & chime", detail: "Feel it land without looking", symbol: "bell.and.waves.left.and.right.fill", color: .teal)
                    }
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
                    Picker(selection: $restHours) {
                        Text("1 hour").tag(1.0)
                        Text("3 hours").tag(3.0)
                        Text("6 hours").tag(6.0)
                        Text("A day").tag(24.0)
                    } label: {
                        SettingLabel("Every-visit pins rest", detail: nil, symbol: "moon.zzz.fill", color: .purple)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("New pins remind you on your next visit, then wait in your list. Every-visit pins come back each time, resting in between so popping in and out doesn't nag.")
                }

                Section {
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
                } header: {
                    Text("Permissions")
                } footer: {
                    Text(permissionsFooter)
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
                    LabeledContent("Places armed", value: "\(engine.regions.count) of 20")
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        SettingLabel("Diagnostics", detail: "Why didn't a pin go off?", symbol: "stethoscope", color: .gray)
                    }
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
            .onChange(of: confirmationSound) { _, value in PinscapeSettings.confirmationSound = value }
            .onChange(of: restHours) { _, value in PinscapeSettings.everyVisitRestHours = value }
            .task {
                if PinStore.isDemo {
                    notificationStatus = .authorized
                } else {
                    notificationStatus = await NotificationManager.authorizationStatus()
                }
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
                    Text(proCardDetail)
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

    private var permissionsFooter: String {
        switch engine.authorization {
        case .authorizedAlways:
            return "Pins can find you with Pinscape closed."
        case .authorizedWhenInUse:
            return "With “While Using”, pins only surface while Pinscape is open on screen. Choose “Always” so they find you when you arrive."
        default:
            return "Without location, Pinscape can't tell when you arrive anywhere."
        }
    }

    private var proCardDetail: String {
        if store.isPro { return "Unlimited pins, groups and stickers. Thank you." }
        let price = store.monthly?.displayPrice ?? "£2.99"
        return "Unlimited pins, place groups, NFC stickers, export. From \(price) a month."
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
        ("waveform", "Voice is transcribed by Apple's on-device speech model. If that isn't available for your language, you type instead; audio is never sent anywhere."),
        ("lock.iphone", "Pins and places live in an encrypted store on this iPhone. No account, no Pinscape servers, no sync."),
        ("location.slash", "No location history. iOS watches your pinned places and tells Pinscape only when you arrive at one."),
        ("map", "Finding shops and addresses uses Apple Maps, which sees each search and the area it's for, just as in the Maps app."),
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

/// The quick-capture steps on their own, opened from the hint on Home.
struct CaptureHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ShortcutsHelpView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
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

/// What happened recently, to answer "why didn't it remind me?" without guessing.
/// Records events and times only, never what you wrote or where you were.
struct DiagnosticsView: View {
    @Environment(LocationEngine.self) private var engine
    @State private var entries = Diagnostics.recent()
    @State private var notifications: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            Section("Now") {
                LabeledContent("Pin store", value: storeText)
                LabeledContent("Location", value: locationText)
                LabeledContent("Notifications", value: notificationText)
                LabeledContent("Places armed", value: "\(engine.regions.count) of 20")
            }
            Section {
                if entries.isEmpty {
                    Text("Nothing to report.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: entry.event.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(entry.event.isProblem ? .orange : .green)
                            Text(entry.event.title)
                                .font(.subheadline.weight(.medium))
                            if let times = entry.times, times > 1 {
                                Text("×\(times)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.date, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !entry.detail.isEmpty {
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Recent")
            } footer: {
                Text("Kept on this iPhone. Records what happened and when, never what you wrote or where you were.")
            }
            Section {
                ShareLink(item: report) {
                    Label("Share report", systemImage: "square.and.arrow.up")
                }
                Button("Clear", role: .destructive) {
                    Diagnostics.clear()
                    entries = []
                }
            }
        }
        .navigationTitle("Diagnostics")
        .refreshable { entries = Diagnostics.recent() }
        .task { notifications = await NotificationManager.authorizationStatus() }
    }

    private var storeText: String {
        switch PinStore.health {
        case .ready: "OK"
        case .demo: "Demo"
        case .unavailable: "Can't open"
        }
    }

    private var locationText: String {
        switch engine.authorization {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied, .restricted: "Off"
        default: "Not asked"
        }
    }

    private var notificationText: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        default: "Not asked"
        }
    }

    private var report: String {
        var lines = ["Pinscape diagnostics", "Store: \(storeText)", "Location: \(locationText)", "Notifications: \(notificationText)", "Places armed: \(engine.regions.count)", ""]
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            let times = (entry.times ?? 1) > 1 ? "  ×\(entry.times ?? 1)" : ""
            lines.append("\(formatter.string(from: entry.date))  \(entry.event.rawValue)\(times)  \(entry.detail)")
        }
        return lines.joined(separator: "\n")
    }
}
