import UserNotifications

/// Whether the app may show notifications.
enum NotificationPermissionStatus: Sendable, Equatable {
    /// Not asked yet.
    case notDetermined
    case allowed
    case denied
}

protocol NotificationPermissionProviding: Sendable {
    func status() async -> NotificationPermissionStatus
    /// Shows the system prompt if not asked yet; returns whether notifications are allowed.
    func request() async -> Bool
}

/// Alerts and sound only: alerts never set a badge.
struct NotificationPermission: NotificationPermissionProviding {
    func status() async -> NotificationPermissionStatus {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .allowed
        default: .denied
        }
    }

    func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
