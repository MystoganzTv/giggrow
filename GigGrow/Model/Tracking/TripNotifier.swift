//
//  TripNotifier.swift
//  GigGrow
//
//  Tells you a drive was recorded, while you still remember taking it.
//
//  Automatic tracking has an awkward property: it works silently, so the only
//  evidence it did anything is a list you have to remember to open. By the
//  time you do, a Tuesday drive is one row among thirty and you can't recall
//  whether it was a delivery or the school run — which is exactly the
//  decision the deduction depends on.
//
//  A notification the moment the car stops turns that into a two-second job
//  while the trip is still in your head. Tapping it goes straight to the log.
//
//  Deliberately not chatty: one notification per recorded drive, none for
//  drives too short to save, and nothing at all unless the driver turned
//  automatic tracking on in the first place.
//

import Foundation
import UserNotifications

@MainActor
enum TripNotifier {

    /// Posted when a notification is tapped, so the root can open the log.
    nonisolated static let openMileageLog = Notification.Name("GigGrow.openMileageLog")

    /// Identifies our own notifications among anyone else's.
    nonisolated static let categoryIdentifier = "GigGrow.tripEnded"

    /// Asks once, and only when tracking is switched on.
    ///
    /// Bundling this with the location prompt would mean two dialogs back to
    /// back for something the driver hasn't seen the value of yet. This runs
    /// after location is granted, so by then they've agreed to the feature
    /// the notification is about.
    static func requestPermissionIfNeeded() async {
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await centre.requestAuthorization(options: [.alert, .sound])
    }

    /// Announces a drive that was actually saved.
    ///
    /// Takes the figures rather than the model: the notification is built
    /// after the save, and holding a SwiftData object across that boundary
    /// is a good way to read a deleted one.
    static func tripEnded(miles: Double, minutes: Int, deduction: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Trip recorded"

        // The number that matters plus the one decision left, in one line.
        // "3.6 miles" alone doesn't tell you there's anything to do.
        let distance = String(format: "%.1f mi", miles)
        let worth = Money.cents(deduction)
        content.body = "\(distance) in \(minutes) min. Worth \(worth) if it was for work — tap to say."

        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        // No trigger: deliver now. The point is that it arrives while you're
        // still sitting in the car.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Delegate

/// Routes a tap on one of our notifications to the mileage log.
///
/// A notification that opens the app to whatever screen it was last on is
/// worse than none: it interrupts, then makes you navigate anyway.
final class TripNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.categoryIdentifier
                == TripNotifier.categoryIdentifier else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: TripNotifier.openMileageLog, object: nil)
        }
    }

    /// Shown even with the app open — you may be looking at another screen,
    /// and the whole point is that it reaches you now.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
