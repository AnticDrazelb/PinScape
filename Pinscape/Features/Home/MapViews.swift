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
    /// The street, for a branch found on Apple Maps.
    var subtitle: String?
    /// The chain or kind of place it belongs to (`RegionCandidate.key`), to find its pins.
    var placeKey: String?

    init(id: String, title: String, coordinate: CLLocationCoordinate2D, radius: Double, symbol: String, colorHex: String, subtitle: String? = nil, placeKey: String? = nil) {
        self.id = id
        self.title = title
        self.coordinate = coordinate
        self.radius = radius
        self.symbol = symbol
        self.colorHex = colorHex
        self.subtitle = subtitle
        self.placeKey = placeKey
    }

    init(_ candidate: RegionCandidate, id: String) {
        self.init(id: id, title: candidate.title, coordinate: candidate.center.coordinate, radius: candidate.radius, symbol: candidate.symbol, colorHex: candidate.colorHex, subtitle: candidate.subtitle, placeKey: candidate.key)
    }

    static func == (lhs: PlaceMarker, rhs: PlaceMarker) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension PlaceMarker {
    /// The point on the circle due east of its centre.
    var edgeCoordinate: CLLocationCoordinate2D {
        let metresPerDegree = 111_320 * cos(coordinate.latitude * .pi / 180)
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude + radius / max(metresPerDegree, 1))
    }

    /// Out along the radius, clear of the place's glyph, where its length is labelled.
    var radiusLabelCoordinate: CLLocationCoordinate2D {
        let along = 0.68
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude + (edgeCoordinate.longitude - coordinate.longitude) * along)
    }
}

/// The map at the top of Home: you, and the places your pins are waiting at.
struct HomeMapCard: View {
    @Environment(LocationEngine.self) private var engine
    var markers: [PlaceMarker]
    /// Pins still waiting to find you.
    var armed: Int

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
                    .fill(statusColor)
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

    /// Pins are "armed" only when iOS can wake Pinscape on arrival; otherwise they're just waiting.
    private var isLive: Bool {
        engine.canSurfaceInBackground || PinStore.isDemo
    }

    private var statusText: String {
        if armed == 0 { return "Drop a pin to start" }
        let pins = armed == 1 ? "1 pin" : "\(armed) pins"
        return isLive ? "\(pins) armed" : "\(pins) waiting"
    }

    private var statusColor: Color {
        guard armed > 0 else { return .secondary }
        return isLive ? .green : .orange
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

/// Every place your pins are waiting at, full screen. "Show all branches" adds every branch of
/// those chains within 50 miles, to plan a trip around; only the nearby ones are watched.
struct PinMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationEngine.self) private var engine
    @Query(filter: #Predicate<Pin> { $0.completedAt == nil }) private var pins: [Pin]
    @Query private var places: [SavedPlace]
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selection: String?
    @State private var showAllBranches = PinscapeSettings.showAllBranches || ProcessInfo.processInfo.arguments.contains("-PinscapeAllBranches")
    @State private var allBranches = AllBranchesModel()

    private var markers: [PlaceMarker] {
        var result = engine.regions.map { PlaceMarker($0.candidate, id: $0.id) }
        for pin in pins {
            let target = PinActions.resolvedTarget(for: pin, places: places)
            guard let center = target.center, !result.contains(where: { $0.title == target.title }) else { continue }
            result.append(PlaceMarker(id: pin.id.uuidString, title: target.title, coordinate: center.coordinate, radius: target.radius, symbol: target.symbol, colorHex: target.colorHex))
        }
        return result
    }

    /// Branches beyond the watched ones, as small dots.
    private var branchMarkers: [PlaceMarker] {
        guard showAllBranches else { return [] }
        let watched = engine.regions.map(\.candidate)
        return allBranches.places.flatMap(\.branches)
            .filter { branch in !watched.contains { $0.key == branch.key && $0.center.distance(to: branch.center) < 50 } }
            .map { PlaceMarker($0, id: "branch|" + GeofencePlanner.regionID(for: $0)) }
    }

    private var selectedMarker: PlaceMarker? {
        markers.first { $0.id == selection } ?? branchMarkers.first { $0.id == selection }
    }

    /// Every chain or kind of place your pins are for, once each.
    private var searchSpecs: [PlaceSearchSpec] {
        var seen = Set<String>()
        return pins
            .flatMap { PinActions.resolvedTarget(for: $0, places: places).searches }
            .filter { seen.insert($0.key).inserted }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selection) {
                UserAnnotation()
                ForEach(branchMarkers) { marker in
                    Annotation(marker.title, coordinate: marker.coordinate) {
                        Circle()
                            .fill(Color(hex: marker.colorHex))
                            .frame(width: selection == marker.id ? 18 : 11, height: selection == marker.id ? 18 : 11)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .animation(.snappy, value: selection)
                    }
                    .annotationTitles(.hidden)
                    .tag(marker.id)
                }
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
            .safeAreaInset(edge: .top) {
                AllBranchesToggle(isOn: showAllBranches, summary: allBranches.summary, isLoading: allBranches.isLoading) {
                    showAllBranches.toggle()
                }
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom) {
                if let marker = selectedMarker {
                    MarkerPinsCard(marker: marker, pins: pins(for: marker), distance: distance(to: marker), isBranch: marker.id.hasPrefix("branch|"))
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selection)
            .animation(.snappy, value: showAllBranches)
            .task { if showAllBranches { await loadBranches() } }
            .onChange(of: showAllBranches) { _, on in
                PinscapeSettings.showAllBranches = on
                if on {
                    Task { await loadBranches() }
                } else {
                    if selection?.hasPrefix("branch|") == true { selection = nil }
                    withAnimation { position = .userLocation(fallback: .automatic) }
                }
            }
            .navigationTitle("Your pins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func loadBranches() async {
        guard let here = engine.location ?? PinscapeSettings.lastKnownPoint.map({ CLLocation(latitude: $0.latitude, longitude: $0.longitude) }) else { return }
        await allBranches.load(searchSpecs, around: here)
        fitBranches(around: here.coordinate)
    }

    /// Steps back far enough to show you and every branch.
    private func fitBranches(around here: CLLocationCoordinate2D) {
        let coordinates = branchMarkers.map(\.coordinate) + [here]
        guard coordinates.count > 1,
              let south = coordinates.map(\.latitude).min(), let north = coordinates.map(\.latitude).max(),
              let west = coordinates.map(\.longitude).min(), let east = coordinates.map(\.longitude).max() else { return }
        let center = CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (north - south) * 1.3 + 0.02, longitudeDelta: (east - west) * 1.3 + 0.02)
        withAnimation(.smooth(duration: 0.8)) {
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private func distance(to marker: PlaceMarker) -> Double? {
        engine.location.map { $0.distance(from: CLLocation(latitude: marker.coordinate.latitude, longitude: marker.coordinate.longitude)) }
    }

    private func pins(for marker: PlaceMarker) -> [Pin] {
        if let key = marker.placeKey, marker.id.hasPrefix("branch|") {
            return pins.filter { PinActions.resolvedTarget(for: $0, places: places).matches(regionKey: key) }
        }
        if let region = engine.regions.first(where: { $0.id == marker.id }) {
            return pins.filter { PinActions.resolvedTarget(for: $0, places: places).matches(regionKey: region.candidate.key) }
        }
        return pins.filter { $0.id.uuidString == marker.id || PinActions.resolvedTarget(for: $0, places: places).title == marker.title }
    }
}

private struct MarkerPinsCard: View {
    let marker: PlaceMarker
    let pins: [Pin]
    var distance: Double?
    /// One of the branches shown for planning, rather than a watched place.
    var isBranch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PlaceGlyph(symbol: marker.symbol, colorHex: marker.colorHex, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(marker.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
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
            if isBranch {
                Button(action: openDirections) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .glassSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// "York Way · 2.4 mi"
    private var detail: String? {
        let parts = [marker.subtitle, distance.map(\.distanceText)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: marker.coordinate))
        item.name = marker.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

/// The switch for the all-branches layer, which doubles as its summary once on.
private struct AllBranchesToggle: View {
    var isOn: Bool
    var summary: String
    var isLoading: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                if isOn && isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isOn ? "storefront.fill" : "storefront")
                        .foregroundStyle(isOn ? Theme.accent : .secondary)
                }
                Text(isOn ? summary : "Show all branches")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if isOn {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassSurface(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Hide all branches. \(summary)" : "Show all branches within 50 miles")
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
