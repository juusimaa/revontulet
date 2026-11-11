import Foundation

/// Which place the main screen shows: the device's position or a municipality the user chose.
enum PlaceSelection: Sendable, Hashable {
    case currentLocation
    /// Statistics Finland municipality code.
    case municipality(code: String)
}

/// Remembers the place selection across launches (FR-010) in the App Group suite, so the widgets
/// read the same value. Stays on the device. Only the app writes it; the extension only reads.
final class PlaceSelectionStore {
    static let key = "placeSelection"
    static let currentLocationValue = "currentLocation"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    var selection: PlaceSelection {
        get {
            switch defaults.string(forKey: Self.key) {
            case nil, Self.currentLocationValue?: .currentLocation
            case let code?: .municipality(code: code)
            }
        }
        set {
            switch newValue {
            case .currentLocation: defaults.set(Self.currentLocationValue, forKey: Self.key)
            case .municipality(let code): defaults.set(code, forKey: Self.key)
            }
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
