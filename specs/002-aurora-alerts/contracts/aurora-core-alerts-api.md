# Contract: AuroraCore Additions for Alerts

Additions to the portable core ([001 aurora-core-api.md](../../001-aurora-main-screen/contracts/aurora-core-api.md)).
Everything here builds and tests on macOS and Linux (verified for the existing core with
Swift 6.2.4 on Linux, research R1). Signatures are indicative; names and shapes are binding. All
types are `Sendable`. Nothing here imports Apple-only frameworks (`tools/check-core-portability.sh`).

## Zones (used by app and service)

```swift
public struct AlertZone: Sendable, Hashable, Codable, Identifiable {
    public var id: String          // station code
    public var station: Station
    public var representativePosition: Coordinate { station.coordinate }
}

public enum AlertZones {
    /// All zones, one per bundled station.
    public static func all() throws -> [AlertZone]
    /// Nearest station to `coordinate` regardless of data; keeps `previous` unless another
    /// station is at least 5 km closer.
    public static func zone(for coordinate: Coordinate, previous: AlertZone.ID?, in zones: [AlertZone]) -> AlertZone
}

public enum AlertThreshold: String, Sendable, Codable, CaseIterable { case moderate, high }
```

## Evaluation and rules (used by the service; tested in the core)

```swift
public struct ZoneCondition: Sendable, Hashable, Codable { /* data-model.md */ }

public actor ZoneEvaluator {
    public init(http: any HTTPClient) throws
    /// Fetches what is due (magnetometer ≤ every 5 min, clouds ≤ every 10 min, all of Finland in
    /// one request each, same as AuroraService) and returns one condition per zone with data.
    /// Throws AuroraServiceError.offline when magnetometer data cannot be fetched.
    public func evaluate(at date: Date) async throws -> [ZoneCondition]
}

public struct ZoneAlertState: Sendable, Hashable, Codable { /* data-model.md */ }
public struct AlertDecision: Sendable, Hashable { public var zoneID: String; public var level: ChanceLevel; public var condition: ZoneCondition }

public enum AlertPolicy {
    /// contracts/alert-rules.md §2, exactly. Pure; no clock, no I/O.
    public static func decide(condition: ZoneCondition, state: ZoneAlertState, now: Date)
        -> (decision: AlertDecision?, state: ZoneAlertState)
    /// Whether a registration with `threshold` receives an alert for `level`.
    public static func admits(_ threshold: AlertThreshold, _ level: ChanceLevel) -> Bool
}
```

`ZoneEvaluator` reuses `FMIClient`, `AuroraService.readings`, `StationSelector`, `SolarPosition`,
`CloudSelector` and `ChanceCalculator`; it adds no new calculation, so an alert and the app's own
result always agree for the same data and position.

## Notification content (used by the service; strings live in the app)

```swift
public struct AlertMessage: Sendable, Hashable {
    public var titleKey: String     // e.g. "alert.title.high"
    public var bodyKey: String      // e.g. "alert.body.someActivity.cloudsUnknown"
    public var arguments: [String]  // [station name]
    public static func make(for decision: AlertDecision) -> AlertMessage
    public static let test: AlertMessage
    /// Every key `make` can return; the app's string catalog test checks all exist in fi, sv, en.
    public static let allKeys: [String]
}
```

See [push-notification.md](push-notification.md).

## HTTP contract types (used by app and service)

```swift
public struct RegistrationUpsert: Sendable, Codable, Equatable { token, zone, threshold }
public struct RegistrationToken: Sendable, Codable, Equatable { token }
public enum AlertAPIError: String, Sendable, Codable { case invalidToken, invalidZone, invalidThreshold, invalidBody }
public enum RegistrationValidation {
    public static func validate(_ upsert: RegistrationUpsert, zones: [AlertZone]) -> AlertAPIError?
}
```

## Device-side sync (used by the app; Android can reuse)

```swift
public protocol AlertAPI: Sendable {
    func upsert(_ registration: RegistrationUpsert) async throws(AlertAPIFailure)
    func delete(_ token: RegistrationToken) async throws(AlertAPIFailure)
    func sendTest(_ token: RegistrationToken) async throws(AlertAPIFailure)
}
public enum AlertAPIFailure: Error, Sendable { case unreachable, rejected(AlertAPIError), rateLimited(retryAfter: TimeInterval), notRegistered }

public protocol AlertSyncStore: Sendable {
    func load() async -> AlertSyncState
    func save(_ state: AlertSyncState) async
}

public actor AlertSync {
    public init(api: any AlertAPI, store: any AlertSyncStore)
    public var state: AlertSyncState { get }
    public func setDesired(_ desired: AlertSyncState.Desired) async     // on, off, threshold
    public func zoneChanged(to zone: AlertZone.ID) async                 // FR-004
    public func tokenChanged(_ token: String) async
    /// Sends what is pending; re-confirms if the last confirmation is ≥ 1 day old. Call on foreground.
    public func sync(now: Date) async
}
```

The URLSession-backed `AlertAPI` lives in the core next to `URLSessionHTTPClient` (portable via
FoundationNetworking). The app provides a UserDefaults `AlertSyncStore`.

## Not in the core

APNs registration and notification permission (app), the HTTP server, APNs sending, SQLite and
scheduling (service shell), UI.
