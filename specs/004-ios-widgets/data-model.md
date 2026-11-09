# Data Model: iOS Widgets

Everything here is derived or device-local. Nothing is sent anywhere. Existing types (`AuroraResult`,
`OutlookSnapshot`, `Place`, `Chance`, `ChanceReason`, `SoonSignal`, `NightOutlook`) are reused
unchanged; see [contracts/widget-core-api.md](contracts/widget-core-api.md) for signatures.

## WidgetSnapshot (AuroraCore, new, not persisted)

What one widget draws at one moment. Built by `WidgetSnapshot.make(result:outlook:now:)`.

| Field | Type | Source / rule |
|---|---|---|
| `level` | `ChanceLevel` | `result.chance.level` |
| `reason` | `ChanceReason` | `result.reason` (the app's own mapping) |
| `cloudsIncluded` | `Bool` | `result.chance.cloudsIncluded`; drives the "clouds not included" note (medium only) |
| `municipalityCode` | `String` | `result.place.municipalityCode`; the shell turns it into a name |
| `stationName` | `String` | `result.reading.station.name` |
| `rValue` | `Double?` | `result.reading.r` |
| `measuredAt` | `Date` | `result.reading.measuredAt`; the "age" shown is relative to this |
| `isStale` | `Bool` | `result.isOutdated(now:)`: older than 30 min, the app's limit (FR-008) |
| `soon` | `SoonSignal?` | `outlook.soon` when the outlook matches the result's place; else nil |
| `tonight` | `NightOutlook?` | the outlook's tonight entry when it matches; else nil |

Rules:

- No value is recomputed here: level, reason and outlook come from the stored objects (FR-002).
- The outlook is used only if its `place.municipalityCode` equals the result's (same rule as the
  app's `matchesCurrentPlace`), so a medium widget never shows another place's outlook.
- `isStale` never becomes false by itself: it is a function of `now`, so each timeline entry gets
  its own snapshot (R2).

## WidgetState (shell, the five designed states)

Chosen by the provider per entry; the views switch on it.

| State | When | Draws |
|---|---|---|
| `current(snapshot)` | A result exists and is not stale | Level, reason, place, age, sky |
| `stale(snapshot)` | A result exists, older than 30 min (also offline with cache) | Last level dimmed, "Old data", age, sky dimmed |
| `noPlace` | No stored selection and no cached result | "Open Revontulet to choose a place", no level |
| `noData(reason)` | The result says no valid R, or the place is out of coverage | The app's "no data" / out-of-coverage wording, no level |
| `placeholder` / `sample` | Redacted loading, and the widget gallery | A plausible sample, clearly a sample |

Transitions: `current → stale` at `measuredAt + 30 min` (second timeline entry, no reload needed);
`stale → current` only when a fetch or the app stores a newer result; `noPlace → current` when the
app stores its first result or a selection.

## Shared store (App Group, device-local)

| Item | Location | Writer(s) | Reader(s) |
|---|---|---|---|
| Last result | `<group>/last-result.json` (`AuroraResult`, atomic write, excluded from backup) | app, widget | app, widget |
| Last outlook | `<group>/last-outlook.json` (`OutlookSnapshot`) | app, widget (medium) | app, widget |
| Place selection | `UserDefaults(suiteName: group)` key `placeSelection` (`currentLocation` or a municipality code) | app only | app, widget |

Validation: an unreadable or undecodable file reads as "no cached value", never as an error, as
today. A selection value that is not a known municipality code reads as `currentLocation`
(existing behaviour). Widgets never write the selection.

## Refresh bookkeeping

None is stored. "Is it fresh?" is derived from the stored result (`computedAt`, place) and the
clock, so there is no second file that could disagree with the cache.

## Entities from the spec

- **Widget snapshot**: above.
- **Selected place**: the stored selection plus, for the current location, the place in the last
  result. The widget never changes it and never requests a fix.
