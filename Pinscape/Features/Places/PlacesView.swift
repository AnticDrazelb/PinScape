import MapKit
import SwiftData
import SwiftUI

/// Your own places ("Mum's house", "Gym"), place groups and NFC stickers.
struct PlacesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @Query(sort: \SavedPlace.createdAt) private var places: [SavedPlace]
    @Query(filter: #Predicate<Pin> { $0.completedAt == nil }) private var pins: [Pin]
    @State private var editing: EditorRoute?
    @State private var paywall: PaywallReason?

    enum EditorRoute: Identifiable {
        case new(SavedPlaceKind)
        case edit(SavedPlace)

        var id: String {
            switch self {
            case .new(let kind): "new-\(kind.rawValue)"
            case .edit(let place): place.id.uuidString
            }
        }
    }

    private func items(_ kind: SavedPlaceKind) -> [SavedPlace] {
        places.filter { $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items(.place)) { place in
                        Button { editing = .edit(place) } label: { PlaceRow(place: place, pinCount: count(for: place)) }
                    }
                    .onDelete { delete(items(.place), at: $0) }
                    Button {
                        add(.place)
                    } label: {
                        Label("Add a place", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Places")
                } footer: {
                    Text(placesFooter)
                }

                Section {
                    ForEach(items(.group)) { group in
                        Button { editing = .edit(group) } label: { PlaceRow(place: group, pinCount: count(for: group)) }
                    }
                    .onDelete { delete(items(.group), at: $0) }
                    Button {
                        add(.group)
                    } label: {
                        Label("New group", systemImage: "square.stack.3d.up.fill")
                    }
                } header: {
                    HStack {
                        Text("Groups")
                        if !store.isPro { ProBadge() }
                    }
                } footer: {
                    Text("One name for several shops: “Supermarkets” fires at Tesco, Aldi or Lidl.")
                }

                Section {
                    ForEach(items(.sticker)) { sticker in
                        Button { editing = .edit(sticker) } label: { PlaceRow(place: sticker, pinCount: count(for: sticker)) }
                    }
                    .onDelete { delete(items(.sticker), at: $0) }
                    Button {
                        add(.sticker)
                    } label: {
                        Label("New sticker", systemImage: "wave.3.right.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("NFC stickers")
                        if !store.hasStickers { ProBadge() }
                    }
                } footer: {
                    Text("Stick one on the pantry door or your desk. Tap it with your iPhone to see what you left there.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Places")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { route in
                switch route {
                case .new(let kind):
                    PlaceEditorView(place: nil, kind: kind)
                case .edit(let place):
                    PlaceEditorView(place: place, kind: place.kind)
                }
            }
            .sheet(item: $paywall) { reason in
                PaywallView(reason: reason)
            }
        }
    }

    private var placesFooter: String {
        let base = "Say “near gym” or “at Mum's” and Pinscape knows where you mean."
        return store.isPro ? base : base + " Free includes \(PinscapePlan.freeSavedPlaces) place."
    }

    private func count(for place: SavedPlace) -> Int {
        pins.filter { $0.place.savedPlaceID == place.id }.count
    }

    private func add(_ kind: SavedPlaceKind) {
        switch kind {
        case .place where !store.isPro && items(.place).count >= PinscapePlan.freeSavedPlaces:
            paywall = .placeLimit
        case .group where !store.isPro:
            paywall = .groups
        case .sticker where !store.hasStickers:
            paywall = .stickers
        default:
            editing = .new(kind)
        }
    }

    private func delete(_ list: [SavedPlace], at offsets: IndexSet) {
        for index in offsets {
            context.delete(list[index])
        }
        PinActions.didChange()
    }
}

struct PlaceRow: View {
    let place: SavedPlace
    let pinCount: Int

    var body: some View {
        HStack(spacing: 12) {
            PlaceGlyph(symbol: place.symbol, colorHex: place.colorHex, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if pinCount > 0 {
                Text("\(pinCount)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
    }

    private var detail: String {
        switch place.kind {
        case .place: [place.address.isEmpty ? nil : place.address, "\(PlaceTarget.formatDistance(place.radius)) radius"].compactMap { $0 }.joined(separator: " · ")
        case .group: place.members.joined(separator: ", ")
        case .sticker: "NFC sticker"
        }
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.gradient, in: Capsule())
    }
}
