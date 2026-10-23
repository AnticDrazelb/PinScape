import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers
import Vision

@MainActor
@Observable
final class ShareModel {
    var note = ""
    var place: PlaceTarget? = nil
    var isAmbient = false
    private(set) var image: UIImage? = nil
    private(set) var link: URL? = nil
    private(set) var linkTitle: String? = nil
    private(set) var spottedBrands: [Brand] = []
    private(set) var lines: [String] = []
    private(set) var isLoading = true
    private(set) var saved = false
    private(set) var limitReached = false
    /// Why the last save failed, if it did. Nothing was stored.
    var errorMessage: String? = nil
    let savedPlaces: [SavedPlace]

    init() {
        savedPlaces = PinActions.savedPlaces()
    }

    var suggestions: [PlaceSuggestion] {
        PlaceSuggester.suggestions(for: note, market: Locale.current.region?.identifier == "US" ? .us : .uk, limit: 4)
            .filter { suggestion in
                if case .brand(let brand) = suggestion.kind { return !spottedBrands.contains(brand) }
                return true
            }
    }

    var canSave: Bool {
        PinStore.isWritable && place != nil && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saved
    }

    func load(_ items: [NSExtensionItem]) async {
        defer { isLoading = false }
        // Check what's been bought now, rather than trusting what the app last saw.
        await Entitlements.refresh()
        var texts: [String] = []
        for item in items {
            if let title = item.attributedContentText?.string, !title.isEmpty {
                linkTitle = linkTitle ?? title
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), image == nil {
                    image = await Self.loadImage(from: provider)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), link == nil {
                    link = (try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)) as? URL
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = (try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)) as? String {
                        texts.append(text)
                    }
                }
            }
        }

        if let text = texts.first, link == nil, image == nil {
            let parsed = CaptureParser(savedPlaceNames: savedPlaces.map(\.name)).parse(text)
            note = parsed.note
            isAmbient = parsed.isAmbient
            if let phrase = parsed.place {
                place = Self.target(for: phrase, places: savedPlaces)
            }
        }

        if let link {
            if let host = link.host, let brand = BrandCatalog.brand(forHost: host) {
                spottedBrands = [brand]
                place = .brand(brand)
            }
            note = Self.tidyTitle(linkTitle ?? texts.first ?? "", brand: spottedBrands.first)
        }

        if let cgImage = image?.cgImage {
            let recognized = await Task.detached(priority: .userInitiated) {
                Self.recognizeText(in: cgImage)
            }.value
            lines = Self.noteCandidates(from: recognized)
            spottedBrands = PlaceSuggester.brandsMentioned(in: recognized.joined(separator: "\n"))
            if let brand = spottedBrands.first {
                place = .brand(brand)
            }
            if note.isEmpty, let first = lines.first {
                note = first
            }
        }
    }

    func save() {
        guard canSave, let place else { return }
        guard PinActions.canAddPin else {
            limitReached = true
            return
        }
        do {
            try PinActions.add(text: CaptureParser.cleanNote(note), place: place, isAmbient: isAmbient, capturedByVoice: false, source: .share)
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A place typed by hand: a known shop, a kind of place, one of yours, or a search.
    func setPlace(typed text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parser = CaptureParser(savedPlaceNames: savedPlaces.map(\.name))
        if let phrase = parser.classify(trimmed), let target = Self.target(for: phrase, places: savedPlaces) {
            place = target
        } else {
            place = .search(TextNormalizer.titleCase(trimmed))
        }
    }

    static func target(for phrase: PlacePhrase, places: [SavedPlace]) -> PlaceTarget? {
        switch phrase.match {
        case .brand(let brand):
            return .brand(brand)
        case .category(let category):
            return category.isSearchable ? .category(category) : nil
        case .saved(let name):
            return places.first { $0.name == name }?.target(near: phrase.isNear)
        case .freeform:
            return .search(phrase.text)
        case .here, .downtown:
            // Needs your location; finish in the app.
            return nil
        }
    }

    // MARK: Helpers

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        if let image = item as? UIImage { return image }
        if let url = item as? URL, let data = try? Data(contentsOf: url) { return UIImage(data: data) }
        if let data = item as? Data { return UIImage(data: data) }
        return nil
    }

    nonisolated private static func recognizeText(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// Lines from a screenshot that read like a product: "Samsung 55" QLED TV", not "£549" or "Add to basket".
    private static func noteCandidates(from lines: [String]) -> [String] {
        let noise = ["add to basket", "add to bag", "add to cart", "buy now", "free delivery", "sign in", "search", "menu", "basket", "checkout", "reviews"]
        var seen = Set<String>()
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let lower = line.lowercased()
                let letters = line.filter(\.isLetter).count
                guard letters >= 4, line.count <= 60, line.split(separator: " ").count >= 2 else { return false }
                guard !noise.contains(where: { lower.contains($0) }) else { return false }
                guard BrandCatalog.brand(named: line) == nil else { return false }
                return seen.insert(lower).inserted
            }
            .prefix(6)
            .map { $0 }
    }

    /// "BEKANT Desk sit/stand - IKEA" → "BEKANT Desk sit/stand"
    private static func tidyTitle(_ title: String, brand: Brand?) -> String {
        var result = title
        if let brand {
            for separator in [" - ", " | ", " – ", " — ", " : "] {
                let parts = result.components(separatedBy: separator)
                if parts.count > 1 {
                    result = parts.filter { BrandCatalog.brand(named: $0.trimmingCharacters(in: .whitespaces)) != brand && !$0.lowercased().contains(brand.name.lowercased()) }.joined(separator: separator)
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
