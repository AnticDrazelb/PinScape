import SwiftUI
import UIKit

struct ShareView: View {
    @Bindable var model: ShareModel
    var close: () -> Void

    @State private var typedPlace = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !PinStore.isWritable {
                        Label(AppGroup.isShared ? "Pinscape can't open your pins right now, so this can't be saved. Open the app for details." : "This copy of Pinscape was installed without an App Group, so the Share Sheet can't save pins. Add this in the app instead.", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    preview
                    noteCard
                    if !model.lines.isEmpty {
                        section("From the screenshot") {
                            chipRow(model.lines) { line in
                                Button {
                                    model.note = line
                                } label: {
                                    Text(line)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.primary.opacity(model.note == line ? 0.14 : 0.06), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    placeSection
                    section("Remind me") {
                        VStack(alignment: .leading, spacing: 8) {
                            RemindModePicker(isAmbient: $model.isAmbient)
                            Text(RemindModePicker.explanation(isAmbient: model.isAmbient))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if model.saved {
                    savedBadge
                }
            }
            .navigationTitle("Drop a Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pin it") {
                        model.save()
                        if model.saved {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            Task {
                                try? await Task.sleep(for: .milliseconds(900))
                                close()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!model.canSave)
                }
            }
            .alert("Not saved", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .tint(Theme.accent)
    }

    // MARK: Pieces

    @ViewBuilder
    private var preview: some View {
        if let image = model.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if model.isLoading {
                        Label("Reading screenshot…", systemImage: "text.viewfinder")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }
        } else if let link = model.link {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.linkTitle ?? link.host ?? "Link")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(link.host ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var noteCard: some View {
        section("Thought") {
            TextField("What should Pinscape remind you?", text: $model.note, axis: .vertical)
                .font(.title3.weight(.medium))
                .lineLimit(1...4)
                .focused($focused)
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var placeSection: some View {
        section("Where") {
            VStack(alignment: .leading, spacing: 12) {
                if let place = model.place {
                    HStack(spacing: 12) {
                        PlaceGlyph(place, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title)
                                .font(.headline)
                            Text(model.spottedBrands.first?.name == place.name ? "Spotted in what you shared" : place.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                let options = placeOptions
                if !options.isEmpty {
                    chipRow(options.indices.map { $0 }) { index in
                        let option = options[index]
                        Button {
                            model.place = option.1
                        } label: {
                            PlaceChip(title: option.0, symbol: option.1.symbol, colorHex: option.1.colorHex, selected: model.place == option.1)
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("Or type a place — “Hobbycraft”, “any pharmacy”", text: $typedPlace)
                    .submitLabel(.done)
                    .onSubmit { model.setPlace(typed: typedPlace) }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var placeOptions: [(String, PlaceTarget)] {
        var options: [(String, PlaceTarget)] = model.spottedBrands.map { ($0.name, PlaceTarget.brand($0)) }
        options += model.suggestions.map { ($0.title, $0.target) }
        options += model.savedPlaces.filter { $0.kind != .sticker }.map { ($0.name, $0.target()) }
        return options
    }

    private var savedBadge: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(Theme.gradient, in: Circle())
            Text("Pinned")
                .font(.title2.weight(.bold))
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .transition(.scale.combined(with: .opacity))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
        }
    }

    private func chipRow<Item: Hashable, Chip: View>(_ items: [Item], @ViewBuilder chip: @escaping (Item) -> Chip) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    chip(item)
                }
            }
        }
        .scrollClipDisabled()
    }
}
