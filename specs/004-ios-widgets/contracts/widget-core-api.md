# Contract: AuroraCore additions for widgets

New, public, Foundation-only API in `Packages/AuroraCore` (builds and tests on macOS and Linux).
Written test-first. Existing API is unchanged.

## WidgetSnapshot

```swift
public struct WidgetSnapshot: Sendable, Hashable {
    public var level: ChanceLevel
    public var reason: ChanceReason
    public var cloudsIncluded: Bool
    public var municipalityCode: String
    public var stationName: String
    public var rValue: Double?
    public var measuredAt: Date
    public var isStale: Bool
    public var soon: SoonSignal?
    public var tonight: NightOutlook?

    public static func make(result: AuroraResult, outlook: OutlookSnapshot?, now: Date) -> WidgetSnapshot
}
```

Behaviour:

- `level`, `reason`, `cloudsIncluded`, `stationName`, `rValue`, `measuredAt` are copied from the
  result. `isStale` is `result.isOutdated(now:)`.
- `soon` and `tonight` come from `outlook` only when its place's municipality code equals the
  result's; otherwise both are nil.
- `tonight` is the outlook entry whose `which == .tonight`, nil when there is none.

Tests: each level and reason copied; stale at 30 min + 1 s and not at exactly 30 min; outlook of
another municipality ignored; missing outlook; missing R value.

## WidgetRefreshPolicy

```swift
public enum WidgetRefreshPolicy {
    /// true when a fetch is needed: no cached result, another municipality, a future computedAt
    /// (clock moved), or the result is older than the magnetometer interval (5 min).
    public static func resultNeedsFetch(cached: AuroraResult?, place: Place, now: Date) -> Bool

    /// Same rule for the outlook snapshot (medium widget only), using its computedAt and the
    /// shortest outlook input interval (5 min).
    public static func outlookNeedsFetch(cached: OutlookSnapshot?, place: Place, now: Date) -> Bool

    /// The reload date to suggest to the system.
    public static func nextReload(after now: Date, at coordinate: Coordinate) -> Date

    /// The moment a result measured at `measuredAt` turns stale (measuredAt + 30 min).
    public static func staleMoment(measuredAt: Date) -> Date
}
```

Behaviour of `nextReload`:

- Not "too light" at `coordinate` now and in the aurora season: `now + 15 min`.
- Otherwise: 15 min before the next time it is not "too light" (scanned in 15-minute steps over
  24 hours, as `AlertSeason` does), never earlier than `now + 15 min`, never later than
  `now + 3 h`.
- Always strictly after `now`.

Tests: fresh vs due at 4:59 / 5:00 / 5:01; other municipality; no cache; polar summer (always
light, 3 h cap); Oulu in December (15 min); dusk approaching; result of `nextReload` always after
`now`; reference positions and times with known darkness.

## MunicipalityNames

```swift
public struct MunicipalityName: Sendable, Hashable {
    public var code: String
    public var nameFi: String
    public var nameSv: String?
    public var representativePoint: Coordinate
    public func displayName(preferSwedish: Bool) -> String
}

public enum MunicipalityNames {
    /// Decodes only code, names and point from the bundled data, never the polygons.
    public static func lookup(code: String) throws -> MunicipalityName?
}
```

Tests: a known code gives the Finnish and Swedish names and the same point as
`PlaceResolver.municipality(code:)`; an unknown code gives nil. The lookup must not allocate the
polygons (checked by decoding with a type that has no polygon field, asserted structurally).

## Not added

- No new chance rules, no new thresholds, no new network requests, no new fetch type. Widgets call
  `AuroraService.refresh(for:at:force:)` and `OutlookService.refresh(for:zoneID:at:force:)` with
  `force: false`, exactly as the app does.
