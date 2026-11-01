# Data Model: Aurora Outlook

All types live in `AuroraCore`, are `Sendable`, `Hashable` and `Codable`, and use Foundation
only as far as it exists on Linux (Principle III). Existing types from
[spec 001's data model](../001-aurora-main-screen/data-model.md) are extended where marked.

## Moon

### `MoonPosition` (new, enum namespace)

Computes, for a coordinate and a date, a `MoonState`. Algorithm in [research.md R4](research.md).

### `MoonState` (new)

| Field | Type | Notes |
|---|---|---|
| `altitude` | `Double` | Topocentric altitude of the centre, degrees, no refraction |
| `illuminatedFraction` | `Double` | 0…1 |
| `phase` | `MoonPhase` | Derived from the elongation and whether it is waxing |
| `isBright` | `Bool` | `altitude > 0 && illuminatedFraction >= 0.5` (chance-rules v2) |

### `MoonPhase` (new)

`new`, `waxingCrescent`, `firstQuarter`, `waxingGibbous`, `full`, `waningGibbous`,
`lastQuarter`, `waningCrescent`: eight names, each covering 1/8 of the cycle centred on its
nominal phase. Localised as `moon.phase.<case>`.

## Chance (extended)

| Type | Change |
|---|---|
| `LimitingFactor` | new case `moon` |
| `ChanceReason` | new case `brightMoon` (`reason.brightMoon`) |
| `ChanceCalculator.chance` | new parameter `moonBright: Bool`; v1 signature removed, every caller passes the moon |
| `AuroraResult` | new field `moon: MoonState` (decoding a v1 cache without it fails, and the cache is treated as empty, as for any undecodable cache) |
| `ZoneCondition` | unchanged shape; its chance now includes the moon at the zone position |

## Soon

### `SolarWindSample` (new)

| Field | Type | Notes |
|---|---|---|
| `time` | `Date` | UTC minute observed at L1 |
| `arrival` | `Date?` | SWPC's modelled arrival time at Earth |
| `bz` | `Double?` | nT, GSM |
| `speed` | `Double?` | km/s |
| `density` | `Double?` | cm⁻³ |

Missing values in the source (null or fill values, see [noaa-data.md](contracts/noaa-data.md))
become nil. Samples are sorted by time and de-duplicated by minute.

### `Band` (new)

`north`, `central`, `south`. `Band.of(zoneID:)` maps station codes as in
[soon-rules.md](contracts/soon-rules.md#bands).

### `SoonState` (new)

`quiet`, `possible`, `likely`, `unknown`. Ordered quiet < possible < likely for hysteresis.

### `SoonSignal` (new)

| Field | Type | Notes |
|---|---|---|
| `state` | `SoonState` | |
| `driver` | `Double?` | Median Ey in mV/m; nil when unknown |
| `arrivalMinutes` | `Int?` | Rounded time remaining (15, 30, 45, 60 = "about an hour"); nil when unknown or quiet |
| `latest` | `SolarWindSample?` | Newest sample with Bz and speed, for the details |
| `dataTime` | `Date?` | Time of `latest` |

## Outlook

### `KpBlock` (new)

| Field | Type | Notes |
|---|---|---|
| `start` | `Date` | UTC; the block covers `start ..< start + 3 h` |
| `kp` | `Double` | 0…9 |
| `kind` | `KpKind` | `observed`, `estimated`, `predicted` |

### `KpForecast` (new)

| Field | Type | Notes |
|---|---|---|
| `blocks` | `[KpBlock]` | Sorted by start |
| `fetchedAt` | `Date` | The product has no issue time; shown as "updated" |

### `StormWatch` (new)

| Field | Type | Notes |
|---|---|---|
| `level` | `Int` | G level 1…5 |
| `days` | `[String]` | UTC days the watch covers, `yyyy-MM-dd` |
| `issuedAt` | `Date` | |

Only the newest watch per UTC day counts; a cancelled watch removes that day (see
[noaa-data.md](contracts/noaa-data.md)).

### `CloudForecast` (new)

| Field | Type | Notes |
|---|---|---|
| `zoneID` | `String` | Station code |
| `hourly` | `[Date: Double]` | Total cloud cover %, UTC hours |
| `fetchedAt` | `Date` | FMI gives no issue time in the simple query; fetch time is shown |

### `Night` (new)

| Field | Type | Notes |
|---|---|---|
| `start`, `end` | `Date?` | nil when the night is too light |
| `relevantStart`, `relevantEnd` | `Date?` | Outlook rules §1 |
| `reachesDark` | `Bool` | |

### `NightOutlook` (new)

| Field | Type | Notes |
|---|---|---|
| `which` | `NightKind` | `tonight`, `tomorrow` |
| `night` | `Night` | |
| `availability` | `OutlookAvailability` | `available`, `tooLight`, `unavailable` |
| `activity` | `ActivityLevel?` | Expected activity |
| `maxKp` | `Double?` | Kp for the night (after watches) |
| `watchLevel` | `Int?` | Highest G level |
| `moon` | `Bool` | Bright for the night |
| `darkness` | `Darkness` | |
| `clouds` | `CloudCondition` | |
| `meanCloudPercent` | `Double?` | |
| `chance` | `Chance?` | nil unless available or too light |
| `reason` | `OutlookReason?` | `ChanceReason` or `stormWatch` |
| `kpFetchedAt`, `cloudsFetchedAt` | `Date?` | For the details (FR-016) |

### `Outlook` (new)

| Field | Type | Notes |
|---|---|---|
| `tonight`, `tomorrow` | `NightOutlook` | |
| `computedAt` | `Date` | |

## Service and cache

### `OutlookService` (new actor)

Owns the NOAA and FMI forecast fetches and their due times (R8), separately from
`AuroraService`, so a failure in one never affects the other (FR-020). It produces a
`SoonSignal` and an `Outlook` for a place and a date, and stores them in an `OutlookCache`.

### `OutlookSnapshot` (new, cached)

| Field | Type | Notes |
|---|---|---|
| `place` | `Place` | The outlook is shown only if it matches the current place |
| `soon` | `SoonSignal` | |
| `outlook` | `Outlook?` | |
| `samples`, `forecast`, `watches`, `clouds` | raw inputs with their fetch times | So the next launch can recompute for a new place or time without the network |

`OutlookCache` is a protocol like `ResultCache`; the app stores it as a separate file in
Application Support, so a corrupt or old snapshot never affects the headline cache.

## State transitions

- **Soon state**: recomputed on every refresh from the newest samples; hysteresis (soon rules
  step 6) uses the previous `SoonSignal.state` for the same place.
- **Outlook**: recomputed on every refresh from the cached inputs, so the "tonight" night
  changes at the end of a dark period even when nothing new was fetched.
