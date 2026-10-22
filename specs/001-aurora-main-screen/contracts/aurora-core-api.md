# Contract: AuroraCore Public API

The interface between the portable core package (`Packages/AuroraCore`) and the platform layers
(iOS now, Android later). Signatures are indicative; names and shapes are binding, details may be
refined during implementation. All types are `Sendable`. Types are described in
[data-model.md](../data-model.md).

## Entry point

```swift
public actor AuroraService {
    public init(http: any HTTPClient, cache: any ResultCache, clock: any Clock<Duration> = .continuous)

    /// Last stored result, if any. Never touches the network (FR-008).
    public func cachedResult() async -> AuroraResult?

    /// Fetches what is due (magnetometer ≤ every 5 min, clouds ≤ every 10 min, or `force`),
    /// computes a new result for `place`, stores it and returns it.
    /// Throws only when there is no data at all; partial failures are reflected in the result.
    public func refresh(for place: Place, at date: Date, force: Bool) async throws -> AuroraResult
}
```

## Place resolution (offline)

```swift
public struct PlaceResolver: Sendable {
    public init() throws            // loads bundled municipalities
    /// Current location → municipality, or .outsideCoverage (FR-001e, FR-003).
    public func resolve(latitude: Double, longitude: Double) -> PlaceResolution
    /// Manual selection search by Finnish or Swedish name, prefix and diacritic insensitive (FR-010).
    public func search(_ text: String, limit: Int) -> [Municipality]
    public func municipality(code: String) -> Municipality?
}

public enum PlaceResolution: Sendable, Equatable {
    case inside(Municipality)
    case outsideCoverage
}
```

## Pure calculations (unit-tested directly)

```swift
public enum RIndex {
    /// 60 differences of 10 s samples ending at `end`; nil if the window has too many gaps.
    public static func compute(samples: [MagnetometerSample], end: Date) -> Double?
}
public enum ActivityClassifier {
    public static func level(r: Double, station: Station) -> ActivityLevel
}
public enum SolarPosition {
    public static func elevation(latitude: Double, longitude: Double, at: Date) -> Double  // degrees
    public static func darkness(latitude: Double, longitude: Double, at: Date) -> Darkness
}
public enum ChanceCalculator {
    /// Implements contracts/chance-rules.md exactly.
    public static func chance(activity: ActivityLevel, darkness: Darkness, clouds: CloudCondition) -> Chance
}
public enum StationSelector {
    /// Nearest station with valid R, with hysteresis (FR-005, edge case: no flip-flopping).
    public static func select(for place: Place, readings: [StationReading], previous: Station.ID?) -> StationReading?
}
```

## Platform-provided protocols

```swift
public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> (Data, Int)   // body, status code
}
public protocol ResultCache: Sendable {
    func load() async -> AuroraResult?
    func save(_ result: AuroraResult) async
}
```

The core ships a default `URLSessionHTTPClient` (works on Apple platforms and, via
FoundationNetworking, on Android). The iOS app provides a file-based `ResultCache` in Application
Support.

## Not in the core

Location permission and updates, persistence of the chosen municipality, UI, localisation of
display strings (the core returns keys and values; the platform formats them).
