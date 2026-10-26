import Foundation
import UIKit
import UserNotifications

/// Asks APNs for this device's token.
@MainActor
protocol PushRegistering {
    func register()
}

struct RemoteNotificationRegistration: PushRegistering {
    func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

extension Notification.Name {
    /// The user opened an aurora alert.
    static let auroraAlertOpened = Notification.Name("auroraAlertOpened")
}

/// Receives the APNs token and notification taps. Requests the token on each launch while alerts
/// are on, as Apple recommends; a changed token replaces the registration (research R13).
final class PushRegistration: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await AppDependencies.alertSettings.registerForPushIfOn() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = Self.hex(deviceToken)
        Task { await AppDependencies.alertSettings.tokenReceived(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Retried on the next launch; the settings keep showing "Waiting to confirm".
    }

    /// An alert arriving while the app is open is shown as a banner too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Opening an alert shows the main screen, which refreshes as usual (no deep link).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { NotificationCenter.default.post(name: .auroraAlertOpened, object: nil) }
    }

    /// Lowercase hex, as the alert service expects.
    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
