import MapKit
import SwiftData
import SwiftUI

struct PinDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationEngine.self) private var engine
    @Query private var matches: [Pin]
    @Query(sort: \SavedPlace.createdAt) private var places: [SavedPlace]
    @State private var showPicker = false
    @State private var confirmDelete = false

    init(pinID: UUID) {
        _matches = Query(filter: #Predicate<Pin> { $0.id == pinID })
    }

    var body: some View {
        NavigationStack {
            if let pin = matches.first {
                content(pin)
            } else {
                ContentUnavailableView("Pin not found", systemImage: "mappin.slash")
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func content(_ pin: Pin) -> some View {
        let target = PinActions.resolvedTarget(for: pin, places: places)
        return List {
            Section {
                VStack(spacing: 10) {
                    PlaceGlyph(target, size: 68)
                        .shadow(color: Color(hex: target.colorHex).opacity(0.4), radius: 14, y: 6)
                    Text(target.title)
                        .font(Theme.roundedTitle(.title2))
                    Text(target.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Change place") {
                        showPicker = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .secondaryButtonStyle()
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("Thought") {
                TextField("What should Pinscape remind you?", text: Binding(
                    get: { pin.text },
                    set: { pin.text = $0 }
                ), axis: .vertical)
                .font(.title3.weight(.medium))
                .lineLimit(1...6)
                .onSubmit { PinActions.didChange() }
            }

            Section {
                RemindModePicker(isAmbient: Binding(
                    get: { pin.isAmbient },
                    set: {
                        pin.isAmbient = $0
                        PinActions.didChange()
                    }
                ))
                if pin.wasReminded {
                    Button {
                        PinActions.rearm(pin.id)
                    } label: {
                        Label("Remind me again next visit", systemImage: "arrow.clockwise")
                    }
                }
            } header: {
                Text("Remind me")
            } footer: {
                Text(RemindModePicker.explanation(isAmbient: pin.isAmbient, wasReminded: pin.wasReminded))
            }

            mapSection(target)

            Section("History") {
                LabeledContent("Dropped") {
                    Text(pin.createdAt, format: .dateTime.day().month().hour().minute())
                }
                LabeledContent("Captured by") {
                    Label(sourceName(pin), systemImage: pin.capturedByVoice ? "waveform" : "keyboard")
                }
                LabeledContent("Surfaced") {
                    Text(Self.timesText(pin.surfaceCount))
                }
                if let last = pin.lastSurfacedAt {
                    LabeledContent("Last time") {
                        Text(last, format: .relative(presentation: .named))
                    }
                }
            }

            Section {
                Button {
                    PinActions.toggleCompleted(pin.id)
                    dismiss()
                } label: {
                    Label(pin.isCompleted ? "Bring back" : "Mark as done", systemImage: pin.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
                ShareLink(item: "\(target.title): \(pin.text)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    PinActions.didChange()
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            PlacePickerView(note: pin.text) { newTarget in
                pin.place = newTarget
                PinActions.didChange()
            }
        }
        .confirmationDialog("Delete this pin?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                PinActions.delete(pin.id)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func mapSection(_ target: PlaceTarget) -> some View {
        let markers = markers(for: target)
        if !markers.isEmpty {
            Section {
                Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                    UserAnnotation()
                    ForEach(markers) { marker in
                        MapCircle(center: marker.coordinate, radius: marker.radius)
                            .foregroundStyle(Color(hex: marker.colorHex).opacity(0.18))
                            .stroke(Color(hex: marker.colorHex), lineWidth: 1.5)
                        Annotation(marker.title, coordinate: marker.coordinate) {
                            PlaceGlyph(symbol: marker.symbol, colorHex: marker.colorHex, size: 26)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
            } header: {
                Text(target.isDynamic ? "Nearest matches" : "Where")
            } footer: {
                if target.isDynamic {
                    Text("Pinscape watches the closest few and swaps in new ones as you move.")
                }
            }
        }
    }

    private func markers(for target: PlaceTarget) -> [PlaceMarker] {
        if let center = target.center {
            return [PlaceMarker(id: "target", title: target.title, coordinate: center.coordinate, radius: target.radius, symbol: target.symbol, colorHex: target.colorHex)]
        }
        return engine.regions
            .filter { target.matches(regionKey: $0.candidate.key) }
            .prefix(6)
            .map { PlaceMarker($0.candidate, id: $0.id) }
    }

    private static func timesText(_ count: Int) -> String {
        if count == 0 { return "Not yet" }
        return count == 1 ? "Once" : "\(count) times"
    }

    private func sourceName(_ pin: Pin) -> String {
        switch pin.source {
        case .app: "Typing"
        case .voice: "Voice"
        case .siri: "Siri"
        case .share: "Share sheet"
        case .widget: "Widget"
        case .sticker: "NFC sticker"
        }
    }
}
