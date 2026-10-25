import AuroraCore
import Foundation

// Stand-ins for the alert service, notification permission and APNs, used with `-uiTestAlertsStub`.

/// Answers every call successfully, in memory, or with `unreachable` fails every call
/// (`-uiTestAlertsUnreachable`).
actor UITestAlertAPI: AlertAPI {
    private let unreachable: Bool
    private var registrations: [String: RegistrationUpsert] = [:]

    init(unreachable: Bool = false) {
        self.unreachable = unreachable
    }

    func upsert(_ registration: RegistrationUpsert) async throws(AlertAPIFailure) {
        if unreachable { throw .unreachable }
        registrations[registration.token] = registration
    }

    func delete(_ token: RegistrationToken) async throws(AlertAPIFailure) {
        if unreachable { throw .unreachable }
        registrations[token.token] = nil
    }

    func sendTest(_ token: RegistrationToken) async throws(AlertAPIFailure) {
        if unreachable { throw .unreachable }
        guard registrations[token.token] != nil else { throw .notRegistered }
    }
}

actor InMemoryAlertSyncStore: AlertSyncStore {
    private var state = AlertSyncState()

    func load() -> AlertSyncState { state }
    func save(_ state: AlertSyncState) { self.state = state }
}

/// Notifications always allowed, without a system prompt.
struct GrantedNotificationPermission: NotificationPermissionProviding {
    func status() async -> NotificationPermissionStatus { .allowed }
    func request() async -> Bool { true }
}

/// Delivers a fixed token at once instead of asking APNs.
struct UITestPushRegistration: PushRegistering {
    func register() {
        Task { await AppDependencies.alertSettings.tokenReceived(String(repeating: "5a", count: 32)) }
    }
}
