import MapKit
import SwiftData
import SwiftUI

struct PlaceMarker: Identifiable, Hashable {
    var id: String
    var title: String
    var coordinate: CLLocationCoordinate2D
    var radius: Double
    var symbol: String
    var colorHex: String

    init(id: String, title: String, coordinate: CLLocationCoordinate2D, radius: Double, symbol: String, colorHex: String) {
        self.id = id
        self.title = title
        self.coordinate = coordinate
        self.radius = radius
        self.symbol = symbol
        self.colorHex = colorHex
    }

    init(_ candidate: RegionCandidate, id: String) {
        self.init(id: id, title: candidate.title, coordinate: candidate.center.coordinate, radius: candidate.radius, symbol: candidate.symbol, colorHex: candidate.colorHex)
    }

    static func == (lhs: PlaceMarker, rhs: PlaceMarker) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The map at the top of Home: you, and the places your pins are waiting at.
struct HomeMapCard: View {
    @Environment(LocationEngine.self) private var engine
    var markers: [PlaceMarker]
    var watching: Int

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $position, interactionModes: []) {
            UserAnnotation()
            ForEach(markers) { marker in
                MapCircle(center: marker.coordinate, radius: marker.radius)
                    .foregroundStyle(Color(hex: marker.colorHex).opacity(0.16))
                    .stroke(Color(hex: marker.colorHex).opacity(0.55), lineWidth: 1)
                Annotation(marker.title, coordinate: marker.coordinate) {
                    PlaceGlyph(symbol: marker.symbol, colorHex: marker.colorHex, size: 26)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Circle()
                    .fill(watching > 0 ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .glassSurface(in: Capsule())
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .glassSurface(in: Circle())
                .padding(12)
        }
        .onAppear(perform: frame)
        .onChange(of: markers.count) { frame() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map of \(markers.count) places with pins near you")
        .accessibilityAddTraits(.isButton)
    }

    private var statusText: String {
        switch watching {
        case 0: return "Drop a pin to start"
        case 1: return "Watching 1 place nearby"
        default: return "Watching \(watching) places nearby"
        }
    }

    private func frame() {
        guard let center = engine.location?.coordinate else {
            position = markers.isEmpty ? .userLocation(fallback: .automatic) : .automatic
            return
        }
        let here = GeoPoint(center)
        let farthest = markers.map { here.distance(to: GeoPoint($0.coordinate)) }.max() ?? 0
        let span = min(max(farthest * 2.3, 1_400), 9_000)
        position = .region(MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span))
    }
}

/// Every place Pinscape is watching, full screen.
struct PinMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationEngine.self) private var engine
    @Query(filter: #Predicate<Pin> { $0.completedAt == nil }) private var pins: [Pin]
    @Query private var places: [SavedPlace]
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selection: String?

    private var markers: [PlaceMarker] {
        var result = engine.regions.map { PlaceMarker($0.candidate, id: $0.id) }
        for pin in pins {
            let target = PinActions.resolvedTarget(for: pin, places: places)
            guard let center = target.center, !result.contains(where: { $0.title == target.title }) else { continue }
            result.append(PlaceMarker(id: pin.id.uuidString, title: target.title, coordinate: center.coordinate, radius: target.radius, symbol: target.symbol, colorHex: target.colorHex))
        }
        return result
    }

    private var selectedMarker: PlaceMarker? {
        markers.first { $0.id == selection }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selection) {
                UserAnnotation()
                ForEach(markers) { marker in
                    MapCircle(center: marker.coordinate, radius: marker.radius)
                        .foregroundStyle(Color(hex: marker.colorHex).opacity(0.14))
                        .stroke(Color(hex: marker.colorHex).opacity(0.6), lineWidth: 1)
                    Annotation(marker.title, coordinate: marker.coordinate) {
                        PlaceGlyph(symbol: marker.symbol, colorHex: marker.colorHex, size: selection == marker.id ? 38 : 30)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            .animation(.snappy, value: selection)
                    }
                    .tag(marker.id)
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .bottom) {
                if let marker = selectedMarker {
                    MarkerPinsCard(marker: marker, pins: pins(for: marker))
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selection)
            .navigationTitle("Watched places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func pins(for marker: PlaceMarker) -> [Pin] {
        if let region = engine.regions.first(where: { $0.id == marker.id }) {
            return pins.filter { PinActions.resolvedTarget(for: $0, places: places).matches(regionKey: region.candidate.key) }
        }
        return pins.filter { $0.id.uuidString == marker.id || PinActions.resolvedTarget(for: $0, places: places).title == marker.title }
    }
}

private struct MarkerPinsCard: View {
    let marker: PlaceMarker
    let pins: [Pin]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PlaceGlyph(symbol: marker.symbol, colorHex: marker.colorHex, size: 34)
                Text(marker.title)
                    .font(.headline)
                Spacer()
                Text(pins.count == 1 ? "1 pin" : "\(pins.count) pins")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(pins.prefix(4)) { pin in
                Label(pin.text, systemImage: pin.isAmbient ? "repeat" : "circle")
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .glassSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// The pins waiting at the place you're at right now.
struct HereNowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Pin> { $0.completedAt == nil }) private var active: [Pin]
    @Query(filter: #Predicate<Pin> { $0.completedAt != nil }) private var done: [Pin]

    var body: some View {
        NavigationStack {
            List {
                if model.visits.isEmpty {
                    ContentUnavailableView("Not at a pinned place", systemImage: "location.slash", description: Text("When you arrive somewhere with pins, they'll be here and on your Lock Screen."))
                        .listRowBackground(Color.clear)
                }
                ForEach(model.visits) { visit in
                    Section {
                        ForEach(pins(for: visit)) { pin in
                            PinRow(pin: pin)
                        }
                    } header: {
                        HStack(spacing: 12) {
                            PlaceGlyph(symbol: visit.symbol, colorHex: visit.colorHex, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text("Arrived \(visit.arrivedAt, format: .relative(presentation: .named))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .textCase(nil)
                        .padding(.bottom, 6)
                    }
                }
            }
            .navigationTitle("You're here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
    }

    private func pins(for visit: Visit) -> [Pin] {
        let ids = Set(visit.pinIDs)
        return (active + done).filter { ids.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
    }
}
