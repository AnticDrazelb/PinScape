import CoreLocation
import Foundation
import Observation
import UIKit

/// Watches the places your pins point at.
///
/// Uses `CLMonitor` circular conditions, which iOS keeps watching even when Pinscape isn't running.
/// When one is satisfied iOS relaunches the app in the background for a few seconds, which is
/// enough to post the arrival notification. Only the fact that a region fired is ever observed;
/// nothing about your location is stored beyond the last known point used for ranking places.
@MainActor
@Observable
final class LocationEngine: NSObject {
    static let shared = LocationEngine()

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var location: CLLocation? = nil
    /// The places being watched right now (excluding the re-plan boundary).
    private(set) var regions: [PlannedRegion] = []
    private(set) var isPlanning = false

    private let manager = CLLocationManager()
    @ObservationIgnored private var monitor: CLMonitor? = nil
    @ObservationIgnored private var monitorTask: Task<Void, Never>? = nil
    @ObservationIgnored private var replanTask: Task<Void, Never>? = nil
    @ObservationIgnored private var lastPlannedLocation: CLLocation? = nil
    @ObservationIgnored private var started = false
    @ObservationIgnored private var wantsAlwaysUpgrade = false
    @ObservationIgnored private var replanAgain = false
    @ObservationIgnored private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
        regions = RegionStore.load().filter { $0.id != GeofencePlanner.boundaryID }
    }

    var hasAccess: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    /// Arrivals only work in the background with "Always".
    var canSurfaceInBackground: Bool {
        authorization == .authorizedAlways
    }

    // MARK: Lifecycle

    func start() {
        guard !started, !PinStore.isDemo else { return }
        started = true
        authorization = manager.authorizationStatus
        location = manager.location
        PinscapeHooks.pinsChanged = { [weak self] in
            self?.scheduleReplan()
        }
        if authorization == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
        }
        Task {
            await self.startMonitor()
            if AppGroup.defaults.bool(forKey: SharedKeys.needsReplan) || self.regions.isEmpty {
                self.scheduleReplan(after: .milliseconds(200))
            }
        }
    }

    /// Asks for When In Use, then straight away for Always: the two-step flow iOS expects.
    func requestAccess() {
        switch authorization {
        case .notDetermined:
            wantsAlwaysUpgrade = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            if AppGroup.defaults.bool(forKey: "askedForAlways") {
                openSettings()
            } else {
                AppGroup.defaults.set(true, forKey: "askedForAlways")
                manager.requestAlwaysAuthorization()
            }
        case .denied, .restricted:
            openSettings()
        default:
            break
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// A recent location fix, asking Core Location for one if needed.
    func currentLocation(maxAge: TimeInterval = 120) async -> CLLocation? {
        if let location, -location.timestamp.timeIntervalSinceNow < maxAge {
            return location
        }
        guard hasAccess else { return location }
        return await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.resumeWaiters(with: self?.location)
            }
        }
    }

    /// Fills in a believable state for screenshots without touching Core Location.
    func showDemo(location: CLLocation, regions: [PlannedRegion]) {
        self.location = location
        self.regions = regions
        authorization = .authorizedAlways
    }

    // MARK: Planning

    func scheduleReplan(after delay: Duration = .milliseconds(600)) {
        if isPlanning {
            replanAgain = true
            return
        }
        replanTask?.cancel()
        replanTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.replan()
        }
    }

    /// Works out which places to watch and hands them to Core Location.
    func replan() async {
        guard !PinStore.isDemo else { return }
        if monitor == nil {
            await startMonitor()
        }
        guard let monitor else { return }
        guard !isPlanning else {
            // Something changed mid-plan; go round again once this one finishes.
            replanAgain = true
            return
        }
        isPlanning = true
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Pinscape planning", expirationHandler: nil)
        defer {
            isPlanning = false
            UIApplication.shared.endBackgroundTask(backgroundTask)
            if replanAgain {
                replanAgain = false
                scheduleReplan()
            }
        }

        let here = hasAccess ? await currentLocation(maxAge: 300) : location
        let pins = PinActions.activePins()
        let places = PinActions.savedPlaces()

        var candidates: [RegionCandidate] = []
        var searches: [String: PlaceSearchSpec] = [:]
        for pin in pins {
            let target = PinActions.resolvedTarget(for: pin, places: places)
            if let key = target.fixedKey, let center = target.center {
                let candidate = RegionCandidate(key: key, title: target.title, subtitle: target.kind == .spot ? target.detail : nil, center: center, radius: target.radius, symbol: target.symbol, colorHex: target.colorHex)
                candidates.append(candidate)
            }
            for spec in target.searches where searches[spec.key] == nil {
                searches[spec.key] = spec
            }
        }
        if let here {
            for spec in searches.values.sorted(by: { $0.key < $1.key }) {
                candidates += await PlaceSearch.shared.branches(for: spec, near: here)
            }
        }

        let userPoint = here.map { GeoPoint($0.coordinate) }
        let plan = GeofencePlanner.plan(candidates: candidates, around: userPoint, refreshDistance: searches.isEmpty ? nil : 3_000)
        await apply(plan, to: monitor)

        regions = plan.regions
        RegionStore.save(plan.all)
        lastPlannedLocation = here
        AppGroup.defaults.set(false, forKey: SharedKeys.needsReplan)
    }

    private func apply(_ plan: GeofencePlan, to monitor: CLMonitor) async {
        let wanted = plan.all
        let wantedIDs = Set(wanted.map(\.id))
        let existing = Set(await monitor.identifiers)

        for id in existing where !wantedIDs.contains(id) || id == GeofencePlanner.boundaryID {
            await monitor.remove(id)
        }
        for region in wanted where !existing.contains(region.id) || region.id == GeofencePlanner.boundaryID {
            let condition = CLMonitor.CircularGeographicCondition(center: region.candidate.center.coordinate, radius: region.candidate.radius)
            await monitor.add(condition, identifier: region.id, assuming: region.startsInside ? .satisfied : .unsatisfied)
        }
    }

    private func startMonitor() async {
        guard monitor == nil else { return }
        let monitor = await CLMonitor("PinscapePlaces")
        guard self.monitor == nil else { return }
        self.monitor = monitor
        monitorTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    guard let self else { return }
                    await self.handle(identifier: event.identifier, state: event.state)
                }
            } catch {
                print("Pinscape: monitor events ended: \(error)")
            }
        }
    }

    private func handle(identifier: String, state: CLMonitor.Event.State) async {
        if identifier == GeofencePlanner.boundaryID {
            if state == .unsatisfied {
                scheduleReplan(after: .milliseconds(100))
            }
            return
        }
        guard let region = regions.first(where: { $0.id == identifier }) ?? RegionStore.load().first(where: { $0.id == identifier }) else {
            return
        }
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Pinscape arrival", expirationHandler: nil)
        switch state {
        case .satisfied:
            await ArrivalCoordinator.arrived(at: region)
        case .unsatisfied:
            await ArrivalCoordinator.left(region)
        default:
            break
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
    }

    // MARK: Delegate callbacks

    fileprivate func authorizationChanged(_ status: CLAuthorizationStatus) {
        let previous = authorization
        authorization = status
        if status == .authorizedWhenInUse, wantsAlwaysUpgrade {
            wantsAlwaysUpgrade = false
            AppGroup.defaults.set(true, forKey: "askedForAlways")
            manager.requestAlwaysAuthorization()
        }
        if status == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
        }
        if previous != status, status == .authorizedAlways || status == .authorizedWhenInUse {
            scheduleReplan()
        }
    }

    fileprivate func received(_ newLocation: CLLocation) {
        location = newLocation
        PinscapeSettings.lastKnownPoint = GeoPoint(newLocation.coordinate)
        resumeWaiters(with: newLocation)
        guard !isPlanning else { return }
        if let lastPlannedLocation {
            if newLocation.distance(from: lastPlannedLocation) > 1_500 {
                scheduleReplan()
            }
        } else if AppGroup.defaults.bool(forKey: SharedKeys.needsReplan) {
            scheduleReplan()
        }
    }

    fileprivate func resumeWaiters(with location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        for waiter in waiters {
            waiter.resume(returning: location)
        }
    }
}

extension LocationEngine: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationChanged(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.received(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.resumeWaiters(with: self.location)
        }
    }
}
