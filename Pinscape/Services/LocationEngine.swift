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
    @ObservationIgnored private var monitorFailures = 0
    @ObservationIgnored private var lastPlanAttempt: Date? = nil
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
            } else {
                await self.reconcile()
            }
        }
    }

    /// Checks that what Core Location watches matches the saved plan (an interrupted plan or a
    /// crash mid-update can leave them apart) and re-plans if not.
    private func reconcile() async {
        guard let monitor else { return }
        let monitored = Set(await monitor.identifiers)
        let planned = Set(RegionStore.load().map(\.id))
        if monitored != planned {
            Diagnostics.record(.planIncomplete, "Monitored \(monitored.count) regions, plan has \(planned.count); re-planning")
            scheduleReplan()
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

    /// How long to wait before trying again after a plan that couldn't be completed.
    private static let retryDelay: Duration = .seconds(5 * 60)

    /// Works out which places to watch and hands them to Core Location.
    ///
    /// Never trades working regions for a guess: if the pins can't be read nothing changes, and a
    /// failed search or missing location fix keeps what was already watched (see
    /// `GeofencePlanner.replan`) and tries again later.
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
        var retry: Duration? = nil
        defer {
            isPlanning = false
            UIApplication.shared.endBackgroundTask(backgroundTask)
            if replanAgain {
                replanAgain = false
                scheduleReplan()
            } else if let retry {
                scheduleReplan(after: retry)
            }
        }

        lastPlanAttempt = Date()
        let pins: [Pin]
        let places: [SavedPlace]
        do {
            guard PinStore.openIfNeeded() else { throw PersistenceError.storeUnavailable }
            pins = try PinActions.fetchActivePins()
            places = try PinActions.fetchSavedPlaces()
        } catch {
            // Not the same as "no pins": an empty plan would disarm everything.
            AppGroup.defaults.set(true, forKey: SharedKeys.needsReplan)
            let reason = error is PersistenceError ? "The pin store isn't open yet" : "Couldn't read pins (\(error.localizedDescription))"
            Diagnostics.record(.planIncomplete, "\(reason), so the places already watched stay as they are")
            retry = Self.retryDelay
            return
        }

        var here = location
        if hasAccess {
            here = await currentLocation(maxAge: 300)
        }
        // Pins that already reminded you don't take up any of iOS's 20 watched places.
        let inputs = GeofencePlanner.inputs(for: PinActions.snapshots(of: pins, places: places))
        var lookups: [String: BranchLookup] = [:]
        if let here {
            for spec in inputs.searches {
                lookups[spec.key] = await PlaceSearch.shared.branches(for: spec, near: here)
            }
        }
        let result = GeofencePlanner.replan(inputs: inputs, lookups: lookups, previous: RegionStore.load(), around: here.map { GeoPoint($0.coordinate) })
        await apply(result.plan, to: monitor, redrawBoundary: here != nil)

        regions = result.plan.regions
        RegionStore.save(result.plan.all)
        if let here {
            lastPlannedLocation = here
        }
        AppGroup.defaults.set(!result.isComplete, forKey: SharedKeys.needsReplan)
        if result.isComplete {
            Diagnostics.record(.planApplied, "\(result.plan.regions.count) regions")
        } else {
            retry = Self.retryDelay
            Diagnostics.record(.planIncomplete, here == nil ? "No location fix, so the places already watched stay as they are" : "Some Apple Maps searches failed, so their places already watched stay as they are")
        }
    }

    /// Removes the regions a plan no longer wants and adds the new ones. The boundary is redrawn
    /// only when there's a location to centre it on; otherwise the one already watched stays.
    private func apply(_ plan: GeofencePlan, to monitor: CLMonitor, redrawBoundary: Bool) async {
        let wanted = plan.all
        let wantedIDs = Set(wanted.map(\.id))
        let existing = Set(await monitor.identifiers)
        let redraw = { (id: String) in redrawBoundary && id == GeofencePlanner.boundaryID }

        for id in existing where !wantedIDs.contains(id) || redraw(id) {
            await monitor.remove(id)
        }
        for region in wanted where !existing.contains(region.id) || redraw(region.id) {
            let condition = CLMonitor.CircularGeographicCondition(center: region.candidate.center.coordinate, radius: region.candidate.radius)
            await monitor.add(condition, identifier: region.id, assuming: region.startsInside ? .satisfied : .unsatisfied)
        }
    }

    private func startMonitor() async {
        guard monitor == nil else { return }
        let monitor = await CLMonitor("PinscapePlaces")
        guard self.monitor == nil else { return }
        self.monitor = monitor
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    guard let self else { return }
                    self.monitorFailures = 0
                    await self.handle(identifier: event.identifier, state: event.state)
                }
                guard !Task.isCancelled else { return }
                await self?.monitorStopped("The event stream ended")
            } catch {
                guard !Task.isCancelled else { return }
                await self?.monitorStopped(error.localizedDescription)
            }
        }
    }

    /// The event stream died: without it no arrival would ever be seen again in this process.
    /// Start a fresh consumer with backoff (2 s, 4 s, … up to 5 minutes), one at a time.
    private func monitorStopped(_ reason: String) async {
        Diagnostics.record(.monitorStopped, reason)
        monitor = nil
        monitorTask = nil
        monitorFailures += 1
        let delay = min(pow(2, Double(monitorFailures)), 300)
        try? await Task.sleep(for: .seconds(delay))
        guard monitor == nil else { return }
        await startMonitor()
        if monitor != nil {
            Diagnostics.record(.monitorRestarted, "After \(monitorFailures) attempt(s)")
            await reconcile()
        }
    }

    private func handle(identifier: String, state: CLMonitor.Event.State) async {
        if identifier == GeofencePlanner.boundaryID {
            if state == .unsatisfied {
                scheduleReplan(after: .milliseconds(100))
            }
            return
        }
        let region = regions.first(where: { $0.id == identifier }) ?? RegionStore.load().first(where: { $0.id == identifier })
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Pinscape arrival", expirationHandler: nil)
        switch state {
        case .satisfied:
            if let region {
                await ArrivalCoordinator.arrived(at: region)
            } else if !PinStore.openIfNeeded() {
                // Woken before first unlock: the plan and pins are still unreadable. Catch up later.
                ArrivalCoordinator.arrived(atUnreadableRegion: identifier)
            }
        case .unsatisfied:
            await ArrivalCoordinator.left(regionID: identifier)
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
        if let lastPlannedLocation, newLocation.distance(from: lastPlannedLocation) > 1_500 {
            scheduleReplan()
        } else if AppGroup.defaults.bool(forKey: SharedKeys.needsReplan) {
            // Pins changed, or the last plan was incomplete. Retry, but not more than every few minutes.
            if let lastPlanAttempt, Date().timeIntervalSince(lastPlanAttempt) < 5 * 60 { return }
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
