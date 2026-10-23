import MapKit
import SwiftData
import SwiftUI

struct PlaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LocationEngine.self) private var engine

    let place: SavedPlace?
    let kind: SavedPlaceKind

    @State private var name: String
    @State private var symbol: String
    @State private var colorHex: String
    @State private var center: GeoPoint?
    @State private var address: String
    @State private var radius: Double
    @State private var members: Set<String>
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var stickerMessage: String?

    static let symbols = [
        "house.fill", "building.2.fill", "figure.strengthtraining.traditional", "heart.fill", "cup.and.saucer.fill",
        "tree.fill", "graduationcap.fill", "briefcase.fill", "cart.fill", "fork.knife", "bed.double.fill", "car.fill",
        "book.fill", "music.note", "pawprint.fill", "star.fill", "refrigerator.fill", "shippingbox.fill", "desktopcomputer", "tag.fill",
    ]
    static let colors = ["#FF4F5A", "#FF9F0A", "#F2B705", "#34C759", "#30B0C7", "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF6FA8", "#A2845E", "#64748B"]

    init(place: SavedPlace?, kind: SavedPlaceKind) {
        self.place = place
        self.kind = kind
        let defaults: (String, String) = switch kind {
        case .place: ("house.fill", "#FF9F0A")
        case .group: ("cart.fill", "#34C759")
        case .sticker: ("tag.fill", "#8B5CF6")
        }
        _name = State(initialValue: place?.name ?? "")
        _symbol = State(initialValue: place?.symbol ?? defaults.0)
        _colorHex = State(initialValue: place?.colorHex ?? defaults.1)
        _center = State(initialValue: place.flatMap { $0.kind == .place ? $0.center : nil })
        _address = State(initialValue: place?.address ?? "")
        _radius = State(initialValue: place?.radius ?? PlaceTarget.savedRadius)
        _members = State(initialValue: Set(place?.members ?? []))
    }

    private var title: String {
        switch kind {
        case .place: place == nil ? "New Place" : "Edit Place"
        case .group: place == nil ? "New Group" : "Edit Group"
        case .sticker: place == nil ? "New Sticker" : "Sticker"
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .place: return center != nil
        case .group: return members.count >= 2
        case .sticker: return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        PlaceGlyph(symbol: symbol, colorHex: colorHex, size: 52)
                        TextField(namePrompt, text: $name)
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                    appearancePicker
                }

                switch kind {
                case .place: locationSections
                case .group: groupSection
                case .sticker: stickerSection
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .task(id: query) { await search() }
            .onAppear(perform: frameMap)
        }
    }

    private var locationFooter: String {
        let place = name.isEmpty ? "here" : name
        let near = PlaceTarget.formatDistance(PlaceTarget.nearRadius)
        return "Tap the map to move it. “Near \(place)” always uses at least \(near)."
    }

    private var groupFooter: String {
        let group = name.isEmpty ? "this group" : name
        return "A pin for “\(group)” surfaces at whichever of these you walk into first."
    }

    private var namePrompt: String {
        switch kind {
        case .place: "Gym, Mum's house, Office"
        case .group: "Supermarkets"
        case .sticker: "Pantry, Desk, Garage"
        }
    }

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex).gradient)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if hex == colorHex {
                                    Circle().strokeBorder(.white, lineWidth: 2.5).padding(3)
                                }
                            }
                            .onTapGesture { colorHex = hex }
                            .accessibilityAddTraits(hex == colorHex ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.vertical, 2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                ForEach(Self.symbols, id: \.self) { candidate in
                    Image(systemName: candidate)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(candidate == symbol ? .white : .secondary)
                        .background(Circle().fill(candidate == symbol ? Color(hex: colorHex) : Color.primary.opacity(0.06)))
                        .onTapGesture { symbol = candidate }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Place

    @ViewBuilder
    private var locationSections: some View {
        Section {
            MapReader { proxy in
                Map(position: $position) {
                    if let center {
                        MapCircle(center: center.coordinate, radius: radius)
                            .foregroundStyle(Color(hex: colorHex).opacity(0.2))
                            .stroke(Color(hex: colorHex), lineWidth: 2)
                        Annotation(name, coordinate: center.coordinate) {
                            PlaceGlyph(symbol: symbol, colorHex: colorHex, size: 30)
                        }
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        center = GeoPoint(coordinate)
                        address = ""
                    }
                }
            }
            .frame(height: 220)
            .listRowInsets(EdgeInsets())

            VStack(alignment: .leading) {
                HStack {
                    Text("Radius")
                    Spacer()
                    Text(PlaceTarget.formatDistance(radius))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $radius, in: 100...1_000, step: 50)
            }
        } header: {
            Text("Location")
        } footer: {
            Text(locationFooter)
        }

        Section {
            Button {
                Task { await useCurrentLocation() }
            } label: {
                Label("Use my current location", systemImage: "location.fill")
            }
            TextField("Search for an address or place", text: $query)
                .autocorrectionDisabled()
            ForEach(results, id: \.self) { item in
                Button {
                    center = GeoPoint(item.placemark.coordinate)
                    address = PlaceSearch.address(of: item) ?? item.name ?? ""
                    if name.isEmpty { name = item.name ?? "" }
                    query = ""
                    frameMap()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Place")
                            .foregroundStyle(.primary)
                        Text(PlaceSearch.address(of: item) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: center) { frameMap() }
    }

    // MARK: Group

    private var groupSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(BrandCatalog.all.filter { $0.market == CaptureModel.market }, id: \.name) { brand in
                    let selected = members.contains(brand.name)
                    PlaceChip(title: brand.name, symbol: brand.category.symbol, colorHex: brand.category.colorHex, selected: selected)
                        .onTapGesture {
                            if selected { members.remove(brand.name) } else { members.insert(brand.name) }
                        }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Shops in this group")
        } footer: {
            Text(groupFooter)
        }
    }

    // MARK: Sticker

    @ViewBuilder
    private var stickerSection: some View {
        Section {
            Button {
                writeSticker()
            } label: {
                Label("Write to an NFC sticker", systemImage: "wave.3.right")
            }
            .disabled(name.isEmpty)
            Button {
                StickerReader.shared.scan { outcome in
                    if case .read(let id) = outcome {
                        stickerMessage = id == place?.id.uuidString ? "That's this sticker." : "That's a different Pinscape sticker."
                    } else if case .failed(let message) = outcome {
                        stickerMessage = message
                    }
                }
            } label: {
                Label("Test a sticker", systemImage: "sensor.tag.radiowaves.forward")
            }
        } header: {
            Text("NFC")
        } footer: {
            Text(stickerMessage ?? "Any blank NTAG sticker works. It only stores a link to this sticker; your pins never leave your iPhone. For a hands-free tap, add a Shortcuts automation that runs “Open Sticker Pins”.")
        }
    }

    // MARK: Actions

    private func save() {
        let target = place ?? SavedPlace(name: name, symbol: symbol, colorHex: colorHex, kind: kind)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.symbol = symbol
        target.colorHex = colorHex
        switch kind {
        case .place:
            if let center { target.center = center }
            target.radius = radius
            target.address = address
        case .group:
            target.members = BrandCatalog.all.map(\.name).filter { members.contains($0) }
        case .sticker:
            break
        }
        if place == nil {
            context.insert(target)
        }
        PinActions.didChange()
        dismiss()
    }

    private func writeSticker() {
        let sticker: SavedPlace
        if let place {
            sticker = place
        } else {
            sticker = SavedPlace(name: name, symbol: symbol, colorHex: colorHex, kind: .sticker)
            context.insert(sticker)
            PinActions.save()
        }
        StickerReader.shared.write(stickerID: sticker.id.uuidString) { outcome in
            switch outcome {
            case .wrote: stickerMessage = "Sticker ready. Tap it any time to see what you left at \(name)."
            case .failed(let message): stickerMessage = message
            case .read: break
            }
        }
    }

    private func useCurrentLocation() async {
        if !engine.hasAccess {
            engine.requestAccess()
            return
        }
        guard let location = await engine.currentLocation(maxAge: 60) else { return }
        center = GeoPoint(location.coordinate)
        address = await PlaceResolver.streetName(for: location) ?? ""
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        results = Array(await PlaceSearch.shared.search(trimmed, near: engine.location?.coordinate).prefix(5))
    }

    private func frameMap() {
        guard kind == .place else { return }
        if let center {
            let span = max(radius * 4, 600)
            position = .region(MKCoordinateRegion(center: center.coordinate, latitudinalMeters: span, longitudinalMeters: span))
        } else {
            position = .userLocation(fallback: .automatic)
        }
    }
}
