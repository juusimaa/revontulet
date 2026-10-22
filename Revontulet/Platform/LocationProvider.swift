import CoreLocation

/// Result of asking for the device's position once.
enum LocationOutcome: Sendable, Equatable {
    case location(latitude: Double, longitude: Double)
    case denied
    case unavailable
}

@MainActor
protocol LocationProviding: AnyObject {
    /// One position fix; asks for "When In Use" permission the first time. No continuous tracking.
    func currentLocation() async -> LocationOutcome
}

/// CoreLocation-backed provider. Reduced accuracy is enough: the position only picks the nearest
/// station, the municipality and the sun's elevation, all on the device.
@MainActor
final class LocationProvider: LocationProviding {
    func currentLocation() async -> LocationOutcome {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    return .denied
                }
                if let location = update.location {
                    return .location(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
            }
        } catch {
            return .unavailable
        }
        return .unavailable
    }
}

/// A fixed answer, for UI tests and previews.
@MainActor
final class FixedLocationProvider: LocationProviding {
    private let outcome: LocationOutcome

    init(_ outcome: LocationOutcome) {
        self.outcome = outcome
    }

    func currentLocation() async -> LocationOutcome {
        outcome
    }
}
