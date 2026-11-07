import AuroraCore
import Foundation

/// Keeps the alert registration state on the device (data-model.md, App).
struct UserDefaultsAlertSyncStore: AlertSyncStore {
    private static let key = "alertSyncState"

    func load() async -> AlertSyncState {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return AlertSyncState() }
        if let state = try? JSONDecoder().decode(AlertSyncState.self, from: data) { return state }
        return Self.recover(from: data)
    }

    /// The stored state could not be decoded (e.g. a field changed): keep what identifies the old
    /// registration and queue it for deletion, so the service does not keep sending to it.
    static func recover(from data: Data) -> AlertSyncState {
        guard let lenient = try? JSONDecoder().decode(Lenient.self, from: data) else { return AlertSyncState() }
        // Off, with the confirmation unknown: AlertSync then deletes the confirmed token's
        // registration as for any unconfirmed turn-off. Never list the live token as stale: turning
        // alerts on again would register it and then delete that registration.
        return AlertSyncState(desired: .disabled, confirmed: nil, confirmedToken: lenient.confirmedToken,
                              token: lenient.token, hasEverEnabled: lenient.confirmedToken != nil)
    }

    /// Every field optional, so one bad field does not lose the rest.
    private struct Lenient: Decodable {
        var token: String?
        var confirmedToken: String?

        enum CodingKeys: String, CodingKey { case token, confirmedToken }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            token = try? container.decodeIfPresent(String.self, forKey: .token)
            confirmedToken = try? container.decodeIfPresent(String.self, forKey: .confirmedToken)
        }
    }

    func save(_ state: AlertSyncState) async {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
