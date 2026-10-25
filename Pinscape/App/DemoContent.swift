import CoreLocation
import Foundation
import SwiftData

/// Sample pins for screenshots and previews. Launch with `-PinscapeDemo YES`;
/// add `-PinscapeScreen capture|places|settings|onboarding|pin|here|map` to open a screen.
@MainActor
enum DemoContent {
    static let kingsCross = GeoPoint(latitude: 51.5316, longitude: -0.1236)

    static func install() {
        let context = PinStore.context
        guard PinActions.activePinCount(in: context) == 0 else { return }

        if ProcessInfo.processInfo.arguments.contains("-PinscapeFirstPin") {
            installFirstPin(in: context)
            return
        }

        let gym = SavedPlace(name: "Gym", symbol: "figure.strengthtraining.traditional", colorHex: "#FF375F", center: GeoPoint(latitude: 51.5299, longitude: -0.1197), radius: 150, address: "Pancras Square")
        let mum = SavedPlace(name: "Mum's house", symbol: "heart.fill", colorHex: "#FF6FA8", center: GeoPoint(latitude: 51.4613, longitude: -0.1156), radius: 150, address: "Brixton")
        let office = SavedPlace(name: "Office", symbol: "building.2.fill", colorHex: "#64748B", center: GeoPoint(latitude: 51.5345, longitude: -0.1250), radius: 200, address: "Granary Square")
        let supermarkets = SavedPlace(name: "Supermarkets", symbol: "cart.fill", colorHex: "#34C759", kind: .group, members: ["Tesco", "Sainsbury's", "Aldi", "Lidl"])
        let pantry = SavedPlace(name: "Pantry", symbol: "tag.fill", colorHex: "#8B5CF6", kind: .sticker)
        for place in [gym, mum, office, supermarkets, pantry] {
            context.insert(place)
        }

        let now = Date()
        func add(_ text: String, _ place: PlaceTarget, ambient: Bool = false, voice: Bool = false, age: TimeInterval) {
            let pin = Pin(text: text, place: place, isAmbient: ambient, capturedByVoice: voice, source: voice ? .voice : .app)
            pin.createdAt = now.addingTimeInterval(-age)
            context.insert(pin)
        }
        func brand(_ name: String) -> PlaceTarget {
            PlaceTarget.brand(BrandCatalog.brand(named: name)!)
        }

        add("Batteries (AA) and bin bags", brand("Tesco"), voice: true, age: 3_600)
        add("Wood stain — the dark one", brand("B&Q"), voice: true, age: 7_200)
        add("Measure the alcove for the Billy shelf", brand("IKEA"), age: 86_400)
        add("Hay fever tablets", brand("Boots"), voice: true, age: 90_000)
        add("Call Dad", PlaceTarget.spot(name: "This bench", center: GeoPoint(latitude: 51.5352, longitude: -0.1203), detail: "Regent's Canal towpath"), ambient: true, voice: true, age: 400_000)
        add("Creative ideas happen here", PlaceTarget.spot(name: "The Lamb", center: GeoPoint(latitude: 51.5225, longitude: -0.1188), radius: 150, category: .pub, detail: "Near Office"), ambient: true, age: 500_000)
        add("Book a PT session", gym.target(near: true), voice: true, age: 20_000)
        add("Water the tomatoes", mum.target(), age: 150_000)
        add("Ask about the TV deal", brand("Currys"), age: 60_000)
        add("Try the bakery Sarah mentioned", PlaceTarget.area(name: "Bristol", center: GeoPoint(latitude: 51.4545, longitude: -2.5879), radius: 4_000, detail: "City of Bristol"), age: 30_000)
        add("Oat milk — the barista one", supermarkets.target(), voice: true, age: 10_000)
        add("Rice and lentils running low", pantry.target(), age: 5_000)

        let seeded = (try? PinActions.fetchActivePins(in: context)) ?? []
        if let callDad = seeded.first(where: { $0.text == "Call Dad" }) {
            callDad.lastSurfacedAt = now.addingTimeInterval(-86_400)
            callDad.surfaceCount = 6
        }
        // Reminded at Boots yesterday, not ticked off yet.
        if let hayFever = seeded.first(where: { $0.text == "Hay fever tablets" }) {
            hayFever.lastSurfacedAt = now.addingTimeInterval(-80_000)
            hayFever.surfaceCount = 1
        }
        let done = Pin(text: "Post the birthday card", place: .category(.postOffice))
        done.createdAt = now.addingTimeInterval(-200_000)
        done.completedAt = now.addingTimeInterval(-100_000)
        context.insert(done)
        try? context.save()

        let regions: [RegionCandidate] = [
            RegionCandidate(key: "brand:tesco", title: "Tesco Express", subtitle: "York Way", center: GeoPoint(latitude: 51.5338, longitude: -0.1222), radius: 150, symbol: "cart.fill", colorHex: "#34C759"),
            RegionCandidate(key: "brand:tesco", title: "Tesco Metro", subtitle: "Euston Road", center: GeoPoint(latitude: 51.5282, longitude: -0.1301), radius: 150, symbol: "cart.fill", colorHex: "#34C759"),
            RegionCandidate(key: "brand:b&q", title: "B&Q", subtitle: "Holloway", center: GeoPoint(latitude: 51.5487, longitude: -0.1148), radius: 150, symbol: "hammer.fill", colorHex: "#FF9500"),
            RegionCandidate(key: "brand:boots", title: "Boots", subtitle: "St Pancras", center: GeoPoint(latitude: 51.5310, longitude: -0.1262), radius: 150, symbol: "cross.case.fill", colorHex: "#FF453A"),
            RegionCandidate(key: "brand:currys", title: "Currys", subtitle: "Tottenham Court Road", center: GeoPoint(latitude: 51.5189, longitude: -0.1340), radius: 150, symbol: "desktopcomputer", colorHex: "#0A84FF"),
            RegionCandidate(key: "brand:ikea", title: "IKEA", subtitle: "Tottenham", center: GeoPoint(latitude: 51.5917, longitude: -0.0563), radius: 200, symbol: "sofa.fill", colorHex: "#5E5CE6"),
        ]
        let plan = GeofencePlanner.plan(candidates: regions + fixedCandidates(), around: kingsCross)
        LocationEngine.shared.showDemo(location: CLLocation(latitude: kingsCross.latitude, longitude: kingsCross.longitude), regions: plan.regions)

        if let tesco = plan.regions.first(where: { $0.candidate.title == "Tesco Express" }),
           let batteries = PinActions.activePins().first(where: { $0.text.hasPrefix("Batteries") }) {
            VisitStore.begin(Visit(regionID: tesco.id, placeKey: tesco.candidate.key, title: tesco.candidate.title, subtitle: tesco.candidate.subtitle, symbol: tesco.candidate.symbol, colorHex: tesco.candidate.colorHex, arrivedAt: now.addingTimeInterval(-240), pinIDs: [batteries.id]))
        }
        AppModel.shared.refreshVisits()
        openRequestedScreen()
    }

    /// Just after the very first capture: one pin, tutorial collapsed to its one-line hint.
    private static func installFirstPin(in context: ModelContext) {
        let pin = Pin(text: "Wood stain — the dark one", place: .brand(BrandCatalog.brand(named: "B&Q")!), capturedByVoice: true, source: .voice)
        pin.createdAt = Date().addingTimeInterval(-90)
        context.insert(pin)
        try? context.save()
        let bq = RegionCandidate(key: "brand:b&q", title: "B&Q", subtitle: "Holloway", center: GeoPoint(latitude: 51.5487, longitude: -0.1148), radius: 150, symbol: "hammer.fill", colorHex: "#FF9500")
        let plan = GeofencePlanner.plan(candidates: [bq], around: kingsCross)
        LocationEngine.shared.showDemo(location: CLLocation(latitude: kingsCross.latitude, longitude: kingsCross.longitude), regions: plan.regions)
        openRequestedScreen()
    }

    /// Made-up branches scattered within 50 miles of King's Cross, for the all-branches screenshot.
    /// The same every run, so screenshots don't jitter.
    static func branches(for spec: PlaceSearchSpec) -> [RegionCandidate] {
        let seed = spec.key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let count = 5 + seed % 11
        let category = spec.category ?? .other
        return (0..<count).map { index in
            let angle = Double(seed % 360) + Double(index) * 137.5
            let distance = 2_500 + 74_000 * Double(index) / Double(count)
            let center = kingsCross.offset(north: cos(angle * .pi / 180) * distance, east: sin(angle * .pi / 180) * distance)
            return RegionCandidate(key: spec.key, title: AllBranchesModel.name(for: spec), subtitle: nil, center: center, radius: PlaceTarget.storeRadius, symbol: category.symbol, colorHex: category.colorHex)
        }
    }

    private static func fixedCandidates() -> [RegionCandidate] {
        let places = PinActions.savedPlaces()
        return PinActions.activePins().compactMap { pin in
            let target = PinActions.resolvedTarget(for: pin, places: places)
            guard let key = target.fixedKey, let center = target.center else { return nil }
            return RegionCandidate(key: key, title: target.title, subtitle: target.detail, center: center, radius: target.radius, symbol: target.symbol, colorHex: target.colorHex)
        }
    }

    private static func openRequestedScreen() {
        let model = AppModel.shared
        switch UserDefaults.standard.string(forKey: "PinscapeScreen") {
        case "capture":
            model.capture = CaptureRequest(text: "B&Q, wood stain — the dark one", listen: false, source: .voice)
        case "capture-empty":
            model.capture = CaptureRequest(text: "", listen: false)
        case "places":
            model.sheet = .places
        case "settings":
            model.sheet = .settings
        case "onboarding":
            model.showOnboarding = true
        case "here":
            model.sheet = .hereNow
        case "map":
            model.sheet = .map
        case "pin":
            if let pin = PinActions.activePins().first(where: { $0.text == "Call Dad" }) {
                model.sheet = .pin(pin.id)
            }
        default:
            break
        }
    }
}
