# Contract: AuroraCore Additions

Additions to the [core API of spec 001](../../001-aurora-main-screen/contracts/aurora-core-api.md).
Signatures are indicative; names and shapes are binding. Types are in
[data-model.md](../data-model.md).

## Moon and chance

```swift
public enum MoonPosition {
    /// Topocentric altitude (degrees, no refraction), illuminated fraction and phase (R4).
    public static func state(latitude: Double, longitude: Double, at date: Date) -> MoonState
}

public enum ChanceCalculator {
    /// chance-rules v2. Replaces the v1 signature; every caller passes the moon.
    public static func chance(activity: ActivityLevel, darkness: Darkness, moonBright: Bool,
                              clouds: CloudCondition) -> Chance
}
```

`AuroraService.refresh` and `ZoneEvaluator.evaluate` compute the moon for the place or zone
position and pass it. `AuroraResult.moon` carries it to the details.

## Soon and outlook

```swift
public actor OutlookService {
    public init(http: any HTTPClient, cache: any OutlookCache)

    /// Last stored snapshot, if any. Never touches the network.
    public func cachedSnapshot() async -> OutlookSnapshot?

    /// Fetches what is due (R8): solar wind ≤ every 5 min; Kp forecast and alerts ≤ every
    /// 60 min; cloud forecast ≤ every 3 h; or all of them when `force`. Each fetch fails on its own and
    /// leaves its last inputs in place. Computes the soon signal and the outlook for `place` at
    /// `date` from the newest inputs, stores the snapshot and returns it. Never throws: missing
    /// inputs give `SoonState.unknown` or an unavailable night.
    public func refresh(for place: Place, zoneID: String, at date: Date, force: Bool) async -> OutlookSnapshot
}

public protocol OutlookCache: Sendable {
    func load() async -> OutlookSnapshot?
    func save(_ snapshot: OutlookSnapshot) async
}

public enum SoonCalculator {
    /// soon-rules.md. Pure; no clock or network.
    public static func signal(samples: [SolarWindSample], band: Band, now: Date,
                              previous: SoonState?) -> SoonSignal
}

public enum OutlookCalculator {
    /// outlook-rules.md. Pure; sun and moon are computed for `place` inside.
    public static func outlook(place: Coordinate, band: Band, now: Date, kp: KpForecast?,
                               watches: [StormWatch], clouds: CloudForecast?) -> Outlook
}
```

## Parsers

```swift
enum NOAAParser {
    static func propagatedSolarWind(_ data: Data) throws -> [SolarWindSample]
    static func kpForecast(_ data: Data) throws -> KpForecast
    static func stormWatches(_ alerts: Data, now: Date) throws -> [StormWatch]
}
```

The cloud forecast reuses `BsWfsParser`, keyed by position, and maps each position back to its
zone.

## Requests

```swift
public enum NOAARequests {      // fixed URLs, no parameters (FR-018); see noaa-data.md
    static let propagatedSolarWind: URL
    static let kpForecast: URL
    static let alerts: URL
}

extension FMIRequests {
    /// Hourly TotalCloudCover forecast for all zone positions in one request (R5).
    public static func cloudForecast(zones: [AlertZone]) -> URL
}
```

## Platform responsibilities (app)

- Run `OutlookService.refresh` next to `AuroraService.refresh` on the same triggers; never wait
  for one before showing the other.
- Store `OutlookSnapshot` in its own file (`FileOutlookCache`).
- Show the sections described in [main-screen-additions.md](main-screen-additions.md).
