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
///
/// The notification delegate methods are main-actor completion-handler versions on purpose: with the
/// `async` versions Swift calls UIKit's completion handler off the main thread, and UIKit then
/// aborts, so tapping an alert crashed the app instead of opening it. UIKit calls the delegate on
/// the main thread; the `@preconcurrency` conformance checks that at run time.
final class PushRegistration: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
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
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Opening an alert shows the main screen, which fetches new data (no deep link).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .auroraAlertOpened, object: nil)
        completionHandler()
    }

    /// Lowercase hex, as the alert service expects.
    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
