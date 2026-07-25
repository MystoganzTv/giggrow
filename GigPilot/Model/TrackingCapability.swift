//
//  TrackingCapability.swift
//  GigPilot
//
//  What the app can actually do right now.
//
//  Settings used to show "Auto mileage tracking · On" and "Shift detection ·
//  Automatic". Neither is true: there is no Core Location work in the app, no
//  background updates, no drive detection. A settings screen that asserts a
//  capability the binary doesn't have is worse than one that admits the gap —
//  the driver stops logging miles because they believe the app is doing it.
//
//  This type is the single place that answers "is that built yet". When the
//  location work lands, flip the flag here and the UI follows.
//

import Foundation

enum TrackingCapability {

    /// Automatic mileage capture via Core Location. Not built.
    static let automaticMileage = false

    /// Detecting shift start/end from driving activity. Not built.
    static let automaticShiftDetection = false

    /// Whether any automatic tracking exists, which decides whether the
    /// Tracking group can offer switches or only an explanation.
    static var hasAnyAutomation: Bool {
        automaticMileage || automaticShiftDetection
    }

    /// Shown in place of a value when the feature isn't there yet.
    static let notYetLabel = "Not yet"
}
