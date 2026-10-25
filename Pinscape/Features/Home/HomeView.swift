import MapKit
import SwiftData
import SwiftUI
import TipKit
import UserNotifications

/// Pins that share a place, shown as one section.
struct PinGroup: Identifiable {
    var id: String
    var target: PlaceTarget
    var pins: [Pin]
    /// Metres to the nearest matching place, if known.
    var distance: Double?
    /// The nearest branch, for chains: "Tesco Express, York Way".
    var nearestTitle: String?
    var isHere: Bool

    var subtitle: String {
        if let nearestTitle { return "Nearest: \(nearestTitle)" }
        return target.summary
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationEngine.self) private var engine
    @Query(filter: #Predicate<Pin> { $0.completedAt == nil }, sort: \Pin.createdAt, order: .reverse) private var pins: [Pin]
    @Query(filter: #Predicate<Pin> { $0.completedAt != nil }, sort: \Pin.createdAt, order: .reverse) private var completed: [Pin]
    @Query(sort: \SavedPlace.createdAt) private var places: [SavedPlace]

    @State private var notificationsAllowed = true
    @State private var showCompleted = false

    @AppStorage("quickCaptureHintDismissed") private var quickHintDismissed = false

    private let actionTip = ActionButtonTip()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HomeMapCard(markers: mapMarkers, armed: pins.filter(\.isArmed).count)
                        .contentShape(Rectangle())
                        .onTapGesture { model.sheet = .map }
                        .accessibilityAction { model.sheet = .map }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if let visit = model.visits.last, !hereGroups.isEmpty {
                    Section {
                        HereNowBanner(visit: visit, pins: hereGroups.flatMap(\.pins))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                permissionSection

                ForEach(CalendarScout.shared.trips) { trip in
                    Section {
                        TripCard(trip: trip)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if pins.isEmpty {
                    Section {
                        TipView(actionTip)
                            .tipBackground(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Section {
                        EmptyPinsView()
                    }
                    .listRowBackground(Color.clear)
                } else if showsQuickCaptureHint {
                    Section {
                        QuickCaptureHint {
                            model.sheet = .captureHelp
                        } dismiss: {
                            withAnimation(.snappy) { quickHintDismissed = true }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                ForEach(groups) { group in
                    Section {
                        ForEach(group.pins) { pin in
                            PinRow(pin: pin)
                                .contentShape(Rectangle())
                                .onTapGesture { model.sheet = .pin(pin.id) }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        withAnimation(.snappy) { PinActions.setCompleted(pin.id, true) }
                                    } label: {
                                        Label("Done", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                    if pin.wasReminded {
                                        Button {
                                            withAnimation(.snappy) { PinActions.rearm(pin.id) }
                                        } label: {
                                            Label("Again", systemImage: "arrow.clockwise")
                                        }
                                        .tint(.orange)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        withAnimation(.snappy) { PinActions.delete(pin.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button("Done", systemImage: "checkmark.circle") { PinActions.setCompleted(pin.id, true) }
                                    if pin.wasReminded {
                                        Button("Remind me next visit", systemImage: "arrow.clockwise") { PinActions.rearm(pin.id) }
                                    }
                                    Button("Edit", systemImage: "pencil") { model.sheet = .pin(pin.id) }
                                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = pin.text }
                                    Divider()
                                    Button("Delete", systemImage: "trash", role: .destructive) { PinActions.delete(pin.id) }
                                }
                        }
                    } header: {
                        PlaceSectionHeader(group: group)
                    }
                }

                if !completed.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showCompleted) {
                            ForEach(completed.prefix(20)) { pin in
                                PinRow(pin: pin)
                            }
                        } label: {
                            Label("\(completed.count) done", systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Color.clear
                    .frame(height: 60)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .navigationTitle("Pinscape")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        model.sheet = .places
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .accessibilityLabel("Places")
                    Button {
                        model.sheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .bottom) {
                CaptureBar()
            }
            .overlay(alignment: .top) {
                if let undo = model.undo {
                    UndoToastView(toast: undo)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.undo)
            .animation(.snappy, value: pins.count)
            .task {
                let status = await NotificationManager.authorizationStatus()
                let allowed: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
                notificationsAllowed = PinStore.isDemo || allowed.contains(status)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var permissionSection: some View {
        if !PinStore.isDemo, !pins.isEmpty, !engine.canSurfaceInBackground {
            Section {
                NoticeCard(
                    symbol: "location.circle.fill",
                    tint: .blue,
                    title: engine.hasAccess ? "Allow “Always” to be reminded" : "Let Pinscape know where you are",
                    message: "Pins surface when you arrive, even with the app closed. Pinscape keeps no location history and has no servers.",
                    action: engine.hasAccess ? "Change to Always" : "Allow Location"
                ) {
                    engine.requestAccess()
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } else if !notificationsAllowed, !pins.isEmpty {
            Section {
                NoticeCard(symbol: "bell.badge.fill", tint: .red, title: "Turn on notifications", message: "That's how a pin finds you when you walk in.", action: "Allow") {
                    Task {
                        if await NotificationManager.authorizationStatus() == .denied {
                            engine.openSettings()
                        } else {
                            notificationsAllowed = await NotificationManager.requestAuthorization()
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// After the first pin the tutorial card shrinks to this one-liner, and goes away once
    /// you've used quick capture, dropped a handful of pins, or closed it.
    private var showsQuickCaptureHint: Bool {
        guard !quickHintDismissed else { return false }
        let everything = pins + completed
        return everything.count < 5 && !everything.contains { $0.source == .widget }
    }

    // MARK: Grouping

    private var groups: [PinGroup] {
        let here = engine.location.map { GeoPoint($0.coordinate) }
        let visitPins = Set(model.visits.flatMap(\.pinIDs))
        var grouped: [String: PinGroup] = [:]
        var order: [String] = []

        for pin in pins {
            let target = PinActions.resolvedTarget(for: pin, places: places)
            let key = Self.groupKey(for: target)
            if grouped[key] == nil {
                order.append(key)
                var group = PinGroup(id: key, target: target, pins: [], distance: nil, nearestTitle: nil, isHere: false)
                if let center = target.center, let here {
                    group.distance = max(0, here.distance(to: center) - target.radius)
                } else if target.isDynamic {
                    func distance(_ region: PlannedRegion) -> Double {
                        guard let here else { return 0 }
                        return region.candidate.center.distance(to: here)
                    }
                    let matching = engine.regions.filter { target.matches(regionKey: $0.candidate.key) }
                    let nearest = matching.min { distance($0) < distance($1) }
                    if let nearest {
                        group.nearestTitle = [TextNormalizer.businessName(nearest.candidate.title), nearest.candidate.subtitle].compactMap { $0 }.joined(separator: ", ")
                        if let here {
                            group.distance = max(0, here.distance(to: nearest.candidate.center) - nearest.candidate.radius)
                        }
                    }
                }
                grouped[key] = group
            }
            grouped[key]?.pins.append(pin)
            if visitPins.contains(pin.id) {
                grouped[key]?.isHere = true
            }
        }

        return order.compactMap { grouped[$0] }.sorted { lhs, rhs in
            if lhs.isHere != rhs.isHere { return lhs.isHere }
            switch (lhs.distance, rhs.distance) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.pins[0].createdAt > rhs.pins[0].createdAt
            }
        }
    }

    private var hereGroups: [PinGroup] {
        groups.filter(\.isHere)
    }

    static func groupKey(for target: PlaceTarget) -> String {
        if let key = target.fixedKey { return key }
        if let sticker = target.stickerID { return "sticker:\(sticker)" }
        let searches = target.searches.map(\.key)
        return searches.isEmpty ? "\(target.kind.rawValue):\(target.title)" : "\(target.kind.rawValue):" + searches.joined(separator: "+")
    }

    // MARK: Map

    private var mapMarkers: [PlaceMarker] {
        var markers: [String: PlaceMarker] = [:]
        let here = engine.location.map { GeoPoint($0.coordinate) }
        for region in engine.regions {
            if let here, here.distance(to: region.candidate.center) > 6_000 { continue }
            markers[region.id] = PlaceMarker(region.candidate, id: region.id)
        }
        for group in groups {
            guard let center = group.target.center else { continue }
            if let here, here.distance(to: center) > 6_000 { continue }
            let id = group.id
            if markers.values.contains(where: { $0.coordinate.latitude == center.latitude && $0.coordinate.longitude == center.longitude }) { continue }
            markers[id] = PlaceMarker(id: id, title: group.target.title, coordinate: center.coordinate, radius: group.target.radius, symbol: group.target.symbol, colorHex: group.target.colorHex)
        }
        return markers.values.sorted { $0.id < $1.id }
    }
}

// MARK: - Rows

struct PinRow: View {
    let pin: Pin

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    PinActions.toggleCompleted(pin.id)
                }
            } label: {
                Image(systemName: pin.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(pin.isCompleted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pin.isCompleted ? "Mark not done" : "Mark done")
            .sensoryFeedback(.success, trigger: pin.isCompleted)

            VStack(alignment: .leading, spacing: 5) {
                Text(pin.text)
                    .font(.body)
                    .strikethrough(pin.isCompleted, color: .secondary)
                    .foregroundStyle(pin.isCompleted ? .secondary : .primary)
                HStack(spacing: 6) {
                    if pin.isAmbient {
                        Badge(text: "Every visit", symbol: "repeat", tint: .purple)
                    } else if pin.wasReminded {
                        Badge(text: "Reminded", symbol: "bell.fill", tint: .orange)
                    }
                    if pin.capturedByVoice {
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.semibold))
                    }
                    Text(pin.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

struct PlaceSectionHeader: View {
    let group: PinGroup

    var body: some View {
        HStack(spacing: 10) {
            PlaceGlyph(group.target, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.target.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(group.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if group.isHere {
                Badge(text: "You're here", symbol: "location.fill", tint: .green)
            } else if let distance = group.distance {
                Text(distance.distanceText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
        .padding(.horizontal, -4)
    }
}

// MARK: - Cards

struct NoticeCard: View {
    var symbol: String
    var tint: Color
    var title: String
    var message: String
    var action: String
    var perform: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action, action: perform)
                    .font(.subheadline.weight(.semibold))
                    .prominentButtonStyle()
                    .tint(tint)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .cardBackground()
    }
}

struct HereNowBanner: View {
    @Environment(AppModel.self) private var model
    let visit: Visit
    let pins: [Pin]

    var body: some View {
        Button {
            model.sheet = .hereNow
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    PlaceGlyph(symbol: visit.symbol, colorHex: visit.colorHex, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YOU'RE AT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .tracking(1.2)
                        Text(visit.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                ForEach(pins.prefix(3)) { pin in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.caption.weight(.bold))
                        Text(pin.text)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(hex: visit.colorHex).gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                    }
            }
            .shadow(color: Color(hex: visit.colorHex).opacity(0.35), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct TripCard: View {
    @Environment(AppModel.self) private var model
    let trip: TripSuggestion

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.teal.gradient)
                VStack(spacing: 0) {
                    Text(trip.date, format: .dateTime.weekday(.abbreviated))
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                    Text(trip.date, format: .dateTime.day())
                        .font(.title3.weight(.bold))
                }
                .foregroundStyle(.white)
            }
            .frame(width: 48, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Off to \(trip.city)")
                    .font(.headline)
                Text("Anything to remember while you're there?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                model.startCapture(text: "\(trip.city), ", place: .area(name: trip.city, center: trip.center, radius: 4_000), listen: true)
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .prominentButtonStyle()
            .buttonBorderShape(.circle)
        }
        .padding(14)
        .cardBackground()
        .contextMenu {
            Button("Not now", systemImage: "xmark") {
                CalendarScout.shared.dismiss(trip)
            }
        }
    }
}

struct EmptyPinsView: View {
    @Environment(AppModel.self) private var model
    private let examples = ["Tesco, batteries", "B&Q: wood stain, the dark one", "near gym, book a PT session", "this bench = call dad"]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Theme.gradient)
                .symbolEffect(.bounce, options: .nonRepeating)
                .padding(.top, 8)
            VStack(spacing: 6) {
                Text("Leave your first thought")
                    .font(Theme.roundedTitle(.title2))
                Text("Say a place and a thought. Pinscape brings it back when you're actually there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 8) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        model.startCapture(text: example, listen: false)
                    } label: {
                        Text("“\(example)”")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// The collapsed "Capture in two seconds" card.
struct QuickCaptureHint: View {
    var open: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: "button.horizontal.top.press.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Capture faster with the Action Button")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide tip")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 11)
        .cardBackground(cornerRadius: 16)
    }
}

/// The always-there capture bar. Voice first, typing one tap away.
struct CaptureBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.startCapture(listen: true)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.gradient)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 42, height: 42)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 8, y: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Drop a thought")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("“Tesco, batteries”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Drop a thought by voice")

            Button {
                model.startCapture(listen: false)
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Type a thought")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .glassSurface(in: Capsule(), interactive: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

struct UndoToastView: View {
    @Environment(AppModel.self) private var model
    let toast: UndoToast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pinned to \(toast.place)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Shake to undo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Undo") {
                model.undoLastCapture()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassSurface(in: Capsule())
        .padding(.horizontal, 16)
    }
}
