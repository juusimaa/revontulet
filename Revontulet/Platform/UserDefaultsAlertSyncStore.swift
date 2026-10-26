import AuroraCore
import Foundation

/// Keeps the alert registration state on the device (data-model.md, App).
struct UserDefaultsAlertSyncStore: AlertSyncStore {
    private static let key = "alertSyncState"

    func load() async -> AlertSyncState {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(AlertSyncState.self, from: data)
        else { return AlertSyncState() }
        return state
    }

    func save(_ state: AlertSyncState) async {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
