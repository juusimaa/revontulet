import CoreLocation
import Synchronization

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
    /// How long to wait for a fix before giving up. Time spent on the permission prompt does not count.
    private let timeout: Duration

    init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
    }

    func currentLocation() async -> LocationOutcome {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        let awaitingPermission = PermissionFlag()
        let timeout = self.timeout
        // Without a deadline the update stream can wait forever, e.g. in a simulator with no location set.
        return await withTaskGroup(of: LocationOutcome.self) { group in
            group.addTask { await Self.firstFix(awaitingPermission: awaitingPermission) }
            group.addTask {
                var waited = Duration.zero
                while waited < timeout {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                    if !awaitingPermission.isSet { waited += .milliseconds(250) }
                }
                return .unavailable
            }
            let outcome = await group.next() ?? .unavailable
            group.cancelAll()
            return outcome
        }
    }

    private nonisolated static func firstFix(awaitingPermission: PermissionFlag) async -> LocationOutcome {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                awaitingPermission.isSet = update.authorizationRequestInProgress
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

/// Whether the permission prompt is showing, shared between the update stream and the timeout.
private final class PermissionFlag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
