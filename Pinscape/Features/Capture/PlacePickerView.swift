import CoreLocation
import SwiftData
import SwiftUI

/// Choose where a thought lives: your places, right here, any branch of a shop, or anything on Apple Maps.
struct PlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(LocationEngine.self) private var engine
    @Query(sort: \SavedPlace.createdAt) private var places: [SavedPlace]

    var note: String
    var onPick: (PlaceTarget) -> Void

    @State private var query = ""
    @State private var results: [PlaceOption] = []
    @State private var isSearching = false
    @State private var findingHere = false

    private var suggestions: [PlaceSuggestion] {
        PlaceSuggester.suggestions(for: note, market: CaptureModel.market, limit: 5)
    }

    private var brands: [Brand] {
        BrandCatalog.all.filter { $0.market == CaptureModel.market }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    browseSections
                } else {
                    searchSections
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Shops, places, addresses")
            .autocorrectionDisabled()
            .task(id: query) {
                await search()
            }
            .navigationTitle("Where?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Browse

    @ViewBuilder
    private var browseSections: some View {
        if !suggestions.isEmpty {
            Section("Suggested for “\(note)”") {
                ForEach(suggestions, id: \.self) { suggestion in
                    row(PlaceOption(target: suggestion.target, title: suggestion.title, subtitle: "Because of “\(suggestion.reason)”"))
                }
            }
        }

        Section {
            Button {
                Task { await pickHere() }
            } label: {
                HStack(spacing: 12) {
                    PlaceGlyph(symbol: "location.fill", colorHex: "#0A84FF", size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Right here")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("This bench, this café, this view")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if findingHere {
                        ProgressView()
                    }
                }
            }
        }

        let ownPlaces = places.filter { $0.kind != .sticker }
        if !ownPlaces.isEmpty {
            Section("Your places") {
                ForEach(ownPlaces) { place in
                    HStack {
                        Button {
                            pick(place.target())
                        } label: {
                            optionLabel(PlaceOption(target: place.target(), title: place.name, subtitle: place.kind == .group ? place.members.joined(separator: ", ") : (place.address.isEmpty ? "Your place" : place.address)))
                        }
                        .buttonStyle(.borderless)
                        if place.kind == .place {
                            Button("Near") {
                                pick(place.target(near: true))
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }

        let stickers = places.filter { $0.kind == .sticker }
        if !stickers.isEmpty {
            Section("Stickers") {
                ForEach(stickers) { sticker in
                    row(PlaceOption(target: sticker.target(), title: sticker.name, subtitle: "When you tap this sticker"))
                }
            }
        }

        Section("Any branch") {
            ForEach(brands, id: \.name) { brand in
                row(PlaceOption(target: .brand(brand), title: brand.name, subtitle: "Any \(brand.name)"))
            }
        }

        Section("Any kind of place") {
            ForEach(PlaceCategory.allCases.filter(\.isSearchable), id: \.self) { category in
                row(PlaceOption(target: .category(category), title: category.anyPhrase, subtitle: "Whichever is nearest when you pass"))
            }
        }
    }

    // MARK: Search

    @ViewBuilder
    private var searchSections: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        Section {
            if let brand = BrandCatalog.brand(named: trimmed) {
                row(PlaceOption(target: .brand(brand), title: "Any \(brand.name)", subtitle: "Whichever one you walk into"))
            } else if let category = CaptureParser.categoryIndex[TextNormalizer.key(trimmed)] {
                row(PlaceOption(target: .category(category), title: category.anyPhrase, subtitle: "Whichever is nearest"))
            } else {
                row(PlaceOption(target: .search(TextNormalizer.titleCase(trimmed)), title: "Anywhere called “\(trimmed)”", subtitle: "Every match near you, as you move"))
            }
        }
        Section {
            if isSearching && results.isEmpty {
                HStack {
                    ProgressView()
                    Text("Searching Apple Maps…")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(results) { option in
                row(option)
            }
        } header: {
            if !results.isEmpty {
                Text("Just this one")
            }
        }
    }

    // MARK: Rows

    private func row(_ option: PlaceOption) -> some View {
        Button {
            pick(option.target)
        } label: {
            optionLabel(option)
        }
    }

    private func optionLabel(_ option: PlaceOption) -> some View {
        HStack(spacing: 12) {
            PlaceGlyph(option.target, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(option.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func pick(_ target: PlaceTarget) {
        onPick(target)
        dismiss()
    }

    private func pickHere() async {
        if !engine.hasAccess {
            engine.requestAccess()
            return
        }
        findingHere = true
        defer { findingHere = false }
        guard let location = await engine.currentLocation(maxAge: 60) else { return }
        let street = await PlaceResolver.streetName(for: location)
        pick(.spot(name: street.map { "Here, \($0)" } ?? "This spot", center: GeoPoint(location.coordinate), detail: street))
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        let items = await PlaceSearch.shared.search(trimmed, near: engine.location?.coordinate, radius: 15_000)
        guard !Task.isCancelled else { return }
        results = items.prefix(8).map { PlaceResolver.option(for: $0) }
        isSearching = false
    }
}
