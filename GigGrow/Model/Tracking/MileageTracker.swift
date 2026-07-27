//
//  MileageTracker.swift
//  GigGrow
//
//  Automatic mileage capture.
//
//  The code here is not the hard part; battery is. A gig driver has the phone
//  out for eight hours running three other apps, and a tracker that flattens
//  the battery gets deleted before it ever saves a deduction. So:
//
//  - Significant location changes are the idle state. They cost almost
//    nothing and wake the app when the phone moves a few hundred metres.
//  - Full GPS runs only once motion says "automotive", and stops again after
//    a few minutes parked.
//  - `pausesLocationUpdatesAutomatically` lets the system stand down when it
//    can tell nothing is happening.
//
//  Accuracy is honest, not flattering: GPS distance typically runs a few per
//  cent under an odometer because it samples a curve as straight segments.
//  The UI says so rather than presenting it as exact.
//

import Foundation
import CoreLocation
import CoreMotion
import SwiftData

@MainActor
@Observable
final class MileageTracker: NSObject {

    // MARK: State

    enum Status: Equatable {
        case off
        case waiting          // armed, watching for movement
        case recording
        case denied
        case restricted

        var isArmed: Bool { self == .waiting || self == .recording }
    }

    /// How the current drive was started. A trip the driver began by hand is
    /// theirs to end: sitting in a queue for ten minutes must not silently
    /// close it, and Core Motion deciding the car stopped must not either.
    enum Mode: Equatable {
        case automatic
        case manual
    }

    private(set) var status: Status = .off
    private(set) var mode: Mode = .automatic
    /// Metres so far in the drive being recorded.
    private(set) var currentDistance: Double = 0
    private(set) var currentStart: Date?
    /// Set when something needs saying — permission downgraded, and such.
    private(set) var notice: String?

    // MARK: Dependencies

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var context: ModelContext?

    private var lastLocation: CLLocation?
    private var lastMovementAt: Date?
    private var idleTimer: Timer?

    /// Set when the driver tapped Start before iOS had asked about location,
    /// so the trip begins as soon as they say yes rather than needing a
    /// second tap on a button that appeared to do nothing.
    private var pendingManualStart = false
    private var wasArmedBeforeManualTrip = false

    /// How long stationary before a drive is considered over. Shorter and a
    /// traffic light ends the trip; longer and a shift's worth of drives
    /// merge into one.
    private var idleTimeout: TimeInterval = 5 * 60

    /// Ignore jitter. A parked phone drifts by a few metres and would
    /// otherwise accumulate miles overnight.
    private let minimumStep: CLLocationDistance = 20
    private let worstAcceptableAccuracy: CLLocationAccuracy = 50

    // MARK: Setup

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        // Nothing is requested until the driver turns tracking on.
    }

    func configure(context: ModelContext, idleMinutes: Int) {
        self.context = context
        idleTimeout = TimeInterval(max(idleMinutes, 1) * 60)
    }

    // MARK: Control

    /// Asks for permission and arms the tracker.
    ///
    /// iOS only grants "Always" after "When In Use", and only via a second
    /// prompt it may defer. Handled as a sequence rather than assumed.
    func enable() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            arm()
        case .authorizedAlways:
            arm()
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        @unknown default:
            status = .denied
        }
    }

    func disable() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        motion.stopActivityUpdates()
        idleTimer?.invalidate()
        finishDrive()
        status = .off
    }

    private func arm() {
        guard status == .off || status == .denied else { return }
        status = .waiting

        // Cheap wake-up. Full GPS stays off until there's reason to think
        // the driver is moving.
        manager.startMonitoringSignificantLocationChanges()

        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] activity in
                guard let self, let activity else { return }
                guard self.mode != .manual || self.status != .recording else { return }
                if activity.automotive && activity.confidence != .low {
                    self.beginDrive()
                } else if activity.stationary && activity.confidence == .high {
                    self.noteStillness()
                }
            }
        } else {
            // No motion coprocessor: fall back to location alone. Costs more
            // battery, which is why it isn't the default path.
            manager.startUpdatingLocation()
        }
    }

    // MARK: Drive lifecycle

    private func beginDrive(mode: Mode = .automatic) {
        // Automatic detection may fire while a manual trip is already running.
        // The driver's own trip wins.
        guard status != .recording else { return }
        guard mode == .manual || status == .waiting else { return }

        if mode == .manual { wasArmedBeforeManualTrip = status.isArmed }
        self.mode = mode
        status = .recording
        currentStart = .now
        currentDistance = 0
        lastLocation = nil
        lastMovementAt = .now

        enableBackgroundUpdatesIfPermitted()
        manager.startUpdatingLocation()
        if mode == .automatic { startIdleTimer() }
    }

    /// Turns on background updates only when iOS will actually allow it.
    ///
    /// `allowsBackgroundLocationUpdates = true` is not a request — it is an
    /// assertion that the app is entitled to it, and Core Location aborts the
    /// process if it isn't:
    ///
    ///     *** Assertion failure in -[CLLocationManager
    ///     setAllowsBackgroundLocationUpdates:]
    ///     Invalid parameter not satisfying: !stayUp ||
    ///     CLClientIsBackgroundable(internal->fClient)
    ///
    /// Two things have to be true: the bundle declares the `location`
    /// background mode, and the driver granted "Always". Checking
    /// authorisation alone wasn't enough — the build settings were writing
    /// UIBackgroundModes in a shape iOS didn't read, so the entitlement was
    /// missing at runtime and tapping Start killed the app.
    ///
    /// Reading the bundle rather than trusting the build means a future
    /// project-file mistake degrades to "no background tracking" instead of
    /// a crash on the one button this screen has.
    private func enableBackgroundUpdatesIfPermitted() {
        guard canRunInBackground, manager.authorizationStatus == .authorizedAlways else {
            manager.allowsBackgroundLocationUpdates = false
            return
        }
        manager.allowsBackgroundLocationUpdates = true
    }

    /// Whether Info.plist actually declares background location.
    private var canRunInBackground: Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") else {
            return false
        }
        // Written as an array normally, but a misconfigured build setting can
        // produce a bare string. Both are handled rather than trusted.
        if let list = modes as? [String] { return list.contains("location") }
        if let single = modes as? String { return single == "location" }
        return false
    }

    private func noteStillness() {
        guard status == .recording, mode == .automatic else { return }
        lastMovementAt = lastMovementAt ?? .now
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
    }

    private func checkIdle() {
        guard status == .recording, mode == .automatic, let last = lastMovementAt else { return }
        guard Date.now.timeIntervalSince(last) >= idleTimeout else { return }
        finishDrive()
    }

    private func finishDrive() {
        idleTimer?.invalidate()
        idleTimer = nil

        defer {
            currentStart = nil
            currentDistance = 0
            lastLocation = nil
            if status == .recording { status = .waiting }
        }

        guard status == .recording,
              let start = currentStart,
              let context else { return }

        // Drop anything too short to be a real trip. A walk to the shop
        // shouldn't land in a tax record.
        let miles = currentDistance / 1_609.344
        guard miles >= 0.3 else { return }

        let record = DriveRecord(
            start: start,
            // The drive ended when movement stopped, not when the timeout
            // expired, or every trip gains five phantom minutes.
            end: lastMovementAt ?? .now,
            distanceMeters: currentDistance
        )
        context.insert(record)
        try? context.save()

        // Back to the cheap state until the next drive.
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: Manual trips

    /// Starts a trip because the driver said so, not because motion did.
    ///
    /// Works whether or not automatic tracking is armed — a driver who leaves
    /// the switch off still gets to record a single trip, and that is the
    /// least surprising reading of a button marked "Start".
    func startManualTrip() {
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingManualStart = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginDrive(mode: .manual)
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        @unknown default:
            status = .denied
        }
    }

    /// Ends the current drive immediately, for the "Stop" button.
    ///
    /// Returns the distance recorded so the screen can say what was saved —
    /// `finishDrive` clears it, and a trip that vanishes into a confirmation
    /// with no number is the kind of thing that makes people stop trusting it.
    @discardableResult
    func finishNow() -> Double {
        let recorded = currentDistance
        lastMovementAt = .now
        finishDrive()

        // A manual trip hands control back to whatever the driver set. If
        // automatic tracking is off, the tracker stands down entirely rather
        // than quietly staying armed.
        if mode == .manual {
            mode = .automatic
            if !wasArmedBeforeManualTrip { disable() }
        }
        return recorded
    }

    /// Throws away the drive in progress without saving it.
    ///
    /// Backing out of a trip you started by mistake shouldn't leave a stub in
    /// the tax record for you to find and delete later.
    func discardCurrentTrip() {
        idleTimer?.invalidate()
        idleTimer = nil
        currentStart = nil
        currentDistance = 0
        lastLocation = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false

        let wasManual = mode == .manual
        mode = .automatic
        status = (wasManual && !wasArmedBeforeManualTrip) ? .off : .waiting
        if status == .off { disable() }
    }

    /// Elapsed seconds in the drive being recorded, for the live readout.
    var currentDuration: TimeInterval {
        guard let currentStart else { return 0 }
        return max(Date.now.timeIntervalSince(currentStart), 0)
    }

    var currentMiles: Double { currentDistance / 1_609.344 }
}

// MARK: - CLLocationManagerDelegate

extension MileageTracker: CLLocationManagerDelegate {

    /// The modern callback. The older `didChangeAuthorization:` variant has
    /// been deprecated since iOS 14 and reports a value that can already be
    /// stale by the time it arrives; this one reads the manager directly.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        Task { @MainActor in
            switch authorization {
            case .authorizedAlways:
                notice = nil
                if pendingManualStart {
                    pendingManualStart = false
                    beginDrive(mode: .manual)
                } else {
                    arm()
                }
            case .authorizedWhenInUse:
                // Usable, but drives ending while the app is closed will be
                // missed. Say so rather than quietly under-recording.
                notice = "GigGrow can only track while it's open. Allow location “Always” to catch drives in the background."
                if pendingManualStart {
                    pendingManualStart = false
                    beginDrive(mode: .manual)
                } else {
                    arm()
                }
            case .denied:
                pendingManualStart = false
                self.status = .denied
                notice = "Location is off, so miles can't be recorded automatically."
            case .restricted:
                self.status = .restricted
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                accumulate(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            // A transient failure isn't worth alarming anyone over; the
            // manager retries on its own.
            if (error as? CLError)?.code == .denied {
                self.status = .denied
            }
        }
    }

    private func accumulate(_ location: CLLocation) {
        // A significant-change wake while merely waiting is the cue to check
        // whether this is a drive, not to start measuring.
        guard status == .recording else { return }

        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= worstAcceptableAccuracy else { return }

        defer { lastLocation = location }
        guard let previous = lastLocation else { return }

        let step = location.distance(from: previous)
        // Below the noise floor it's a parked phone drifting, not movement.
        guard step >= minimumStep else { return }

        currentDistance += step
        lastMovementAt = location.timestamp
    }
}
