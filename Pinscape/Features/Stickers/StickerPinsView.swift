import SwiftData
import SwiftUI

/// What you left on an NFC sticker, shown when you tap it.
struct StickerPinsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query private var stickers: [SavedPlace]
    @Query(filter: #Predicate<Pin> { $0.completedAt == nil }) private var pins: [Pin]

    let stickerID: UUID

    init(stickerID: UUID) {
        self.stickerID = stickerID
        _stickers = Query(filter: #Predicate<SavedPlace> { $0.id == stickerID })
    }

    private var stickerPins: [Pin] {
        pins.filter { $0.place.savedPlaceID == stickerID }
    }

    private var waitingText: String {
        let count = stickerPins.count
        return count == 0 ? "Nothing left here yet." : "\(count) waiting here"
    }

    var body: some View {
        NavigationStack {
            List {
                if let sticker = stickers.first {
                    Section {
                        VStack(spacing: 10) {
                            PlaceGlyph(symbol: sticker.symbol, colorHex: sticker.colorHex, size: 64)
                            Text(sticker.name)
                                .font(Theme.roundedTitle(.title2))
                            Text(waitingText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        ForEach(stickerPins) { pin in
                            PinRow(pin: pin)
                        }
                        Button {
                            let target = sticker.target()
                            dismiss()
                            Task {
                                try? await Task.sleep(for: .milliseconds(350))
                                app.startCapture(text: "\(sticker.name), ", place: target, listen: true, source: .sticker)
                            }
                        } label: {
                            Label("Leave something here", systemImage: "plus.circle.fill")
                        }
                    }
                } else {
                    ContentUnavailableView("Unknown sticker", systemImage: "tag.slash", description: Text("This sticker isn't set up on this iPhone. Add it in Places › NFC stickers."))
                }
            }
            .navigationTitle("Sticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
