import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct WidgetPin: Identifiable, Hashable {
    let id: UUID
    let text: String
    let place: String
    let symbol: String
    let colorHex: String
    let isAmbient: Bool
}

struct PinsEntry: TimelineEntry {
    let date: Date
    let pins: [WidgetPin]
    let total: Int
    /// The place you're at, if any.
    let here: String?
    /// The pins can't be read from here, e.g. an install without an App Group.
    var isUnavailable = false

    static let sample = PinsEntry(date: .now, pins: [
        WidgetPin(id: UUID(), text: "Batteries and bin bags", place: "Tesco", symbol: "cart.fill", colorHex: "#34C759", isAmbient: false),
        WidgetPin(id: UUID(), text: "Wood stain — the dark one", place: "B&Q", symbol: "hammer.fill", colorHex: "#FF9500", isAmbient: false),
        WidgetPin(id: UUID(), text: "Hay fever tablets", place: "Boots", symbol: "cross.case.fill", colorHex: "#FF453A", isAmbient: false),
        WidgetPin(id: UUID(), text: "Call Dad", place: "This bench", symbol: "mappin", colorHex: "#FF5A4E", isAmbient: true),
        WidgetPin(id: UUID(), text: "Measure the alcove", place: "IKEA", symbol: "sofa.fill", colorHex: "#5E5CE6", isAmbient: false),
    ], total: 9, here: nil)
}

struct PinsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinsEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (PinsEntry) -> Void) {
        completion(context.isPreview ? .sample : Self.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinsEntry>) -> Void) {
        completion(Timeline(entries: [Self.load()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    static func load() -> PinsEntry {
        guard PinStore.isWritable else {
            return PinsEntry(date: .now, pins: [], total: 0, here: nil, isUnavailable: true)
        }
        let context = ModelContext(PinStore.container)
        let descriptor = FetchDescriptor<Pin>(
            predicate: #Predicate<Pin> { $0.completedAt == nil },
            sortBy: [SortDescriptor(\Pin.createdAt, order: .reverse)]
        )
        let pins = (try? context.fetch(descriptor)) ?? []
        let visits = VisitStore.current()
        let herePins = Set(visits.flatMap(\.pinIDs))
        // Pins at the place you're at come first.
        let ordered = pins.filter { herePins.contains($0.id) } + pins.filter { !herePins.contains($0.id) }
        let items = ordered.prefix(8).map { pin in
            let place = pin.place
            return WidgetPin(id: pin.id, text: pin.text, place: place.title, symbol: place.symbol, colorHex: place.colorHex, isAmbient: pin.isAmbient)
        }
        return PinsEntry(date: .now, pins: Array(items), total: pins.count, here: visits.last?.title)
    }
}

/// Your waiting pins on the Home Screen and Lock Screen, tick-off-able in place.
struct PinsWidget: Widget {
    let kind = "PinsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinsProvider()) { entry in
            PinsWidgetView(entry: entry)
        }
        .configurationDisplayName("Waiting Pins")
        .description("The thoughts you've left around town. Tick them off right here.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct PinsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PinsEntry

    var body: some View {
        if entry.isUnavailable {
            unavailable
        } else {
            content
        }
    }

    /// Rather than "0 pins", which would look like your pins were gone.
    @ViewBuilder
    private var unavailable: some View {
        if family == .accessoryInline {
            Label("Open Pinscape", systemImage: "mappin.and.ellipse")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Pinscape", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Text("Open the app to see your pins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(URL(string: "pinscape://open"))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label(entry.here.map { "At \($0)" } ?? "\(entry.total) pins waiting", systemImage: "mappin.and.ellipse")
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        case .systemLarge:
            list(limit: 6)
        default:
            list(limit: 3)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                Text(entry.here ?? "\(entry.total) waiting")
                    .font(.headline)
                    .widgetAccentable()
            }
            ForEach(entry.pins.prefix(2)) { pin in
                Text("\(pin.text) · \(pin.place)")
                    .font(.caption)
                    .lineLimit(1)
            }
            if entry.pins.isEmpty {
                Text("Tap to drop a thought")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: entry.here == nil ? "pinscape://capture" : "pinscape://here"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(entry.total)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "#FF4F5A"))
                    .frame(width: 34, height: 34)
                    .background(.white, in: Circle())
            }
            Text(entry.total == 1 ? "pin waiting" : "pins waiting")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
            if let pin = entry.pins.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.text)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(pin.place)
                        .font(.caption2.weight(.medium))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
            } else {
                Text("Drop a thought")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(hex: "#FF8A3D"), Color(hex: "#FF4F5A"), Color(hex: "#F0367E")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "pinscape://capture"))
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(entry.here.map { "At \($0)" } ?? "Pinscape")
                    .font(.headline)
                Spacer()
                Text("\(entry.total) waiting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button(intent: OpenCaptureIntent()) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.gradient, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if entry.pins.isEmpty {
                Spacer()
                Text("Nothing pinned. Say “Tesco, batteries” and it'll wait for you there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.pins.prefix(limit)) { pin in
                    HStack(spacing: 10) {
                        Button(intent: CompletePinIntent(pinID: pin.id)) {
                            Image(systemName: "circle")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pin.text)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(pin.place)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        PlaceGlyph(symbol: pin.symbol, colorHex: pin.colorHex, size: 22)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
        .widgetURL(URL(string: "pinscape://capture"))
    }
}

/// A one-tap capture button for the Lock Screen and Home Screen.
struct CaptureWidget: Widget {
    let kind = "CaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinsProvider()) { entry in
            CaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Drop a Pin")
        .description("Open Pinscape listening, straight from your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PinsEntry

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 22, weight: .semibold))
                        .widgetAccentable()
                }
                .containerBackground(for: .widget) { Color.clear }
            } else {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 84, height: 84)
                        Circle()
                            .fill(.white)
                            .frame(width: 62, height: 62)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color(hex: "#FF4F5A"))
                    }
                    Text("Drop a thought")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(hex: "#FF8A3D"), Color(hex: "#FF4F5A"), Color(hex: "#F0367E")], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .widgetURL(URL(string: "pinscape://capture"))
    }
}
