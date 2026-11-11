import Foundation

/// The App Group the app and the widget extension share (contracts/shared-storage.md).
enum AppGroup {
    static let identifier = "group.fi.juusimaa.revontulet"

    /// The group container, or Application Support when the container is unavailable (for example
    /// unit tests on the simulator without the entitlement).
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? URL.applicationSupportDirectory
    }

    /// The shared defaults suite, or the standard defaults if the suite cannot be created.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
