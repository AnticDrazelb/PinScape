import CoreLocation
import EventKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationEngine.self) private var engine
    @Query(sort: \Pin.createdAt, order: .reverse) private var allPins: [Pin]

    @State private var voiceConfirmation = PinscapeSettings.voiceConfirmation
    @State private var shakeToUndo = PinscapeSettings.shakeToUndo
    @State private var confirmationSound = PinscapeSettings.confirmationSound
    @State private var restHours = PinscapeSettings.everyVisitRestHours
    @State private var arrivalChime = PinscapeSettings.arrivalChime
    @State private var quietReason: String?
    @State private var testSent = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var calendarOn = CalendarScout.shared.isAuthorized
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    appCard
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Only what needs you. A working setup shows nothing here.
                if !attention.isEmpty {
                    Section {
                        ForEach(attention) { item in
                            attentionRow(item)
                        }
                    }
                }

                Section("Capture") {
                    NavigationLink {
                        ShortcutsHelpView()
                    } label: {
                        SettingLabel("Action Button, Siri & wake phrase", symbol: "button.horizontal.top.press.fill", color: .indigo)
                    }
                    Toggle(isOn: $confirmationSound) {
                        SettingLabel("Sound & haptic", symbol: "bell.and.waves.left.and.right.fill", color: .teal)
                    }
                    Toggle(isOn: $voiceConfirmation) {
                        SettingLabel("Speak confirmation", symbol: "speaker.wave.2.fill", color: .pink)
                    }
                    Toggle(isOn: $shakeToUndo) {
                        SettingLabel("Shake to undo", symbol: "iphone.radiowaves.left.and.right", color: .orange)
                    }
                }

                Section {
                    Picker(selection: $arrivalChime) {
                        Text("Pinscape chime").tag(true)
                        Text("Standard").tag(false)
                    } label: {
                        SettingLabel("Sound", symbol: "bell.badge.fill", color: .red)
                    }
                    Button {
                        Task { await sendTestArrival() }
                    } label: {
                        SettingLabel("Test sound", detail: testSent ? "Plays in 5 seconds. Lock your iPhone to hear it." : nil, symbol: "play.fill", color: .red)
                    }
                    .foregroundStyle(.primary)
                    Picker(selection: $restHours) {
                        Text("1 hour").tag(1.0)
                        Text("3 hours").tag(3.0)
                        Text("6 hours").tag(6.0)
                        Text("A day").tag(24.0)
                    } label: {
                        SettingLabel("Every-visit rest", symbol: "moon.zzz.fill", color: .purple)
                    }
                    Button {
                        Task { await toggleCalendar() }
                    } label: {
                        LabeledContent {
                            Text(calendarOn ? "On" : "Off")
                        } label: {
                            SettingLabel("Trip suggestions", symbol: "calendar", color: .teal)
                        }
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Arrivals")
                } footer: {
                    if let quietReason {
                        Text(quietReason)
                    }
                }

                Section {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        SettingLabel("Privacy", symbol: "hand.raised.fill", color: .blue)
                    }
                    ShareLink(item: exportText, subject: Text("Pinscape pins")) {
                        SettingLabel("Export to Notes", symbol: "square.and.arrow.up", color: .yellow)
                    }
                    .foregroundStyle(.primary)
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        SettingLabel("Clear completed pins", symbol: "trash.fill", color: .gray)
                    }
                    .foregroundStyle(.primary)
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        SettingLabel("Diagnostics", symbol: "stethoscope", color: .gray)
                    }
                } footer: {
                    Text("Pinscape \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
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
            .onChange(of: arrivalChime) { _, value in PinscapeSettings.arrivalChime = value }
            .task { await refreshNotifications() }
        }
    }

    // MARK: Needs attention

    private enum Attention: String, Identifiable {
        case location, notifications, notShared
        var id: String { rawValue }
    }

    private var attention: [Attention] {
        guard !PinStore.isDemo else { return [] }
        var items: [Attention] = []
        if !engine.canSurfaceInBackground { items.append(.location) }
        if notificationStatus == .denied || notificationStatus == .notDetermined { items.append(.notifications) }
        if !AppGroup.isShared { items.append(.notShared) }
        return items
    }

    @ViewBuilder
    private func attentionRow(_ item: Attention) -> some View {
        switch item {
        case .location:
            let off = engine.authorization == .denied || engine.authorization == .restricted
            Button {
                engine.requestAccess()
            } label: {
                AttentionLabel(off ? "Location is off" : "Allow location “Always”", detail: off ? "Pinscape can't tell when you arrive." : "So pins find you with Pinscape closed.")
            }
        case .notifications:
            Button {
                Task {
                    if notificationStatus == .notDetermined {
                        await NotificationManager.requestAuthorization()
                        await refreshNotifications()
                    } else {
                        openNotificationSettings()
                    }
                }
            } label: {
                AttentionLabel(notificationStatus == .denied ? "Notifications are off" : "Turn on notifications", detail: "So arrivals can reach you.")
            }
        case .notShared:
            AttentionLabel("Widgets & Share Sheet are off", detail: "Reinstall with AltStore or SideStore to turn them on.")
        }
    }

    // MARK: Actions

    private func refreshNotifications() async {
        if PinStore.isDemo {
            notificationStatus = .authorized
            return
        }
        notificationStatus = await NotificationManager.authorizationStatus()
        quietReason = await NotificationManager.quietReason()
    }

    private func sendTestArrival() async {
        if notificationStatus == .notDetermined {
            await NotificationManager.requestAuthorization()
        }
        await NotificationManager.postTestArrival()
        testSent = true
        await refreshNotifications()
    }

    private func toggleCalendar() async {
        if CalendarScout.shared.status == .notDetermined {
            calendarOn = await CalendarScout.shared.requestAccess()
        } else {
            // Granted or refused in iOS Settings, which is the only place to change it.
            engine.openSettings()
        }
    }

    /// Pinscape's own page in Settings › Notifications.
    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var appCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Pinscape")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(waitingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }

    private var waitingText: String {
        let waiting = allPins.filter { !$0.isCompleted }.count
        return waiting == 1 ? "1 pin waiting" : "\(waiting) pins waiting"
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

/// A row in Settings that needs you: an orange mark, what's wrong, and one short line on why.
private struct AttentionLabel: View {
    var title: String
    var detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The privacy details, one tap away rather than in the middle of Settings.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            PrivacyCard()
                .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingLabel: View {
    var title: String
    var detail: String?
    var symbol: String
    var color: Color

    init(_ title: String, detail: String? = nil, symbol: String, color: Color) {
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
                "Say “Hey Siri, pin a thought in Pinscape”.",
                "Siri asks “What should I pin?”. Say what and where in one go: “Batteries at Tesco”.",
                "When you arrive somewhere: “What's pinned here in Pinscape?”",
            ])
            HelpStep(symbol: "waveform.badge.mic", color: .purple, title: "Your own wake phrase", steps: [
                "Open Settings › Accessibility › Vocal Shortcuts and tap Set Up Vocal Shortcut.",
                "Choose Siri Request and type “Pin a thought in Pinscape”, or pick the Pin a Thought shortcut.",
                "Say the phrase you want, like “Pin it”, three times when asked.",
                "Now just say “Pin it”, no “Hey Siri” needed, then “Batteries at Tesco”.",
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
    @State private var quiet: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Pin store", value: storeText)
                LabeledContent("Widgets & Share Sheet", value: AppGroup.isShared ? "Shared" : "Off (no App Group)")
                LabeledContent("Location", value: locationText)
                LabeledContent("Notifications", value: notificationText)
                LabeledContent("Arrival sound", value: quiet == nil ? "On" : "May be silent")
                LabeledContent("Shop locations watched", value: "\(engine.regions.count)")
            } header: {
                Text("Now")
            } footer: {
                Text("A pin for “any Boots” watches the nearest few Boots, swapped as you move. iOS lets an app watch 20 locations at once.")
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
        .task {
            notifications = await NotificationManager.authorizationStatus()
            quiet = await NotificationManager.quietReason()
        }
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
        var lines = ["Pinscape diagnostics", "Store: \(storeText)", "Location: \(locationText)", "Notifications: \(notificationText)", "Arrival sound: \(quiet ?? "On")", "Places armed: \(engine.regions.count)", ""]
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            let times = (entry.times ?? 1) > 1 ? "  ×\(entry.times ?? 1)" : ""
            lines.append("\(formatter.string(from: entry.date))  \(entry.event.rawValue)\(times)  \(entry.detail)")
        }
        return lines.joined(separator: "\n")
    }
}
