//
//  MileageTracker.swift
//  GigPilot
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

    private(set) var status: Status = .off
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

    private func beginDrive() {
        guard status == .waiting else { return }
        status = .recording
        currentStart = .now
        currentDistance = 0
        lastLocation = nil
        lastMovementAt = .now

        manager.allowsBackgroundLocationUpdates =
            manager.authorizationStatus == .authorizedAlways
        manager.startUpdatingLocation()
        startIdleTimer()
    }

    private func noteStillness() {
        guard status == .recording else { return }
        lastMovementAt = lastMovementAt ?? .now
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
    }

    private func checkIdle() {
        guard status == .recording, let last = lastMovementAt else { return }
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

    /// Ends the current drive immediately, for the "Stop" button.
    func finishNow() {
        lastMovementAt = .now
        finishDrive()
    }
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
                arm()
            case .authorizedWhenInUse:
                // Usable, but drives ending while the app is closed will be
                // missed. Say so rather than quietly under-recording.
                notice = "GigPilot can only track while it's open. Allow location “Always” to catch drives in the background."
                arm()
            case .denied:
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
