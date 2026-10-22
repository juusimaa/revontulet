# Implementation Plan: Aurora Main Screen

**Branch**: `main` (solo pre-release workflow) | **Date**: 2026-10-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-aurora-main-screen/spec.md`

## Summary

A native iOS main screen that shows the chance of seeing the aurora (None / Low / Moderate / High
with a reason) at the user's location in Finland. The app computes FMI's R value on the device
from FMI open magnetometer data, classifies it with FMI's per-station thresholds, and combines it
with darkness (computed sun elevation) and cloud cover (nearest FMI weather station) using a fixed,
documented rule. Place names, Finland coverage and manual municipality selection use bundled
Statistics Finland boundaries, so no location information leaves the device. All domain logic sits
in a portable Swift package (`AuroraCore`); the SwiftUI app is a thin shell. See
[research.md](research.md).

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency (Xcode 27.1)

**Primary Dependencies**: SwiftUI, CoreLocation (app only); Foundation / FoundationNetworking
(core). No third-party dependencies.

**Storage**: Last result as a JSON file in Application Support (via the core's `ResultCache`
protocol); place selection in UserDefaults; reference data (stations, municipalities) bundled as
package resources.

**Testing**: Swift Testing for `AuroraCore` (unit, table-driven, recorded FMI fixtures); XCTest UI
tests for the main screen with a stubbed HTTP client.

**Target Platform**: iOS 26.0+ (iPhone). Core also builds with `swift build` on macOS and is kept
portable to Android (Swift SDK for Android 6.4.1).

**Project Type**: Mobile app (iOS) + portable Swift package.

**Performance Goals**: Cached result visible ≤ 1 s after launch (SC-002); R and chance computation
for all stations < 50 ms; parsing off the main actor.

**Constraints**: No backend; FMI open data only; no precise location off the device; FMI limits
(20,000 req/day, 600 per 5 min) — app uses ≤ 18 req/h in the foreground only; offline-capable via
cache; fi/sv/en.

**Scale/Scope**: One screen plus a municipality picker and a details area; 10 magnetometer
stations, ~106 cloud stations, 308 municipalities.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Open Data Only | Runtime data only from FMI open data (CC BY 4.0) and Statistics Finland (CC BY 4.0); attribution shown in the details area; request cadence well below FMI limits. FMI's chart endpoint is used only by a development tool to record test reference values, never by the app. | Pass |
| II. Privacy by Design | Both FMI requests cover all of Finland and contain nothing user-derived; place name and coverage resolved on the device from bundled data; "When In Use" location, reduced accuracy is enough; manual municipality selection without network; no analytics or SDKs; result cache stays on the device. | Pass |
| III. Shared Core, Native Shells | All fetching, parsing, R, classification, solar position, chance rules, station selection, place resolution and caching rules in `AuroraCore` with no Apple-only imports and no `XMLParser`; `swift build`/`swift test` work without the app. | Pass |
| IV. Test-First Where Feasible | Core developed test-first against recorded fixtures and reference tables; UI flows covered by UI tests with stubs. | Pass |
| V. Performance & Efficiency | Cache shown before any network work; foreground-only refresh every 5/10 min; one request per data type; computation off the main actor. | Pass |
| VI. Native, Polished UX | Liquid Glass and system materials; level communicated as text; Dynamic Type, VoiceOver, Dark Mode, Reduce Motion/Transparency; explicit states; data age always shown; UI built with the `ios-ui-craft` skill. | Pass |
| Constraints | Swift 6 + SwiftUI, SwiftPM only, no backend, AGPL-3.0 (no third-party code). | Pass |

**Post-design re-check (after Phase 1)**: Pass. The design artifacts introduce no new
dependencies or data flows. One accepted trade-off, not a violation: computing R from open data
can differ from fmi.fi near a threshold, so FR-002 and SC-003 were amended with a tolerance (see
Spec amendments).

## Spec amendments from research

Applied to [spec.md](spec.md) in this planning step:

- FR-002 / SC-003: R is computed from open data with FMI's published definition; it must match
  FMI's published values within ±3, and the activity level must match whenever FMI's R is more than
  3 from a threshold.
- FR-006 / Assumptions: R is updated every 5 minutes (not hourly); results are marked outdated
  after 30 minutes.
- Assumptions: 10 of FMI's 12 stations are available in open data (Nurmijärvi and Sodankylä are
  not).

## Project Structure

### Documentation (this feature)

```text
specs/001-aurora-main-screen/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── aurora-core-api.md
│   ├── chance-rules.md
│   ├── fmi-open-data.md
│   └── main-screen-states.md
├── checklists/requirements.md
└── tasks.md             # created by /speckit-tasks
```

### Source Code (repository root)

```text
Revontulet.xcodeproj
Revontulet/                       # iOS app target (thin native shell)
├── App/                          # RevontuletApp, dependency wiring
├── MainScreen/                   # MainScreenView, MainScreenModel (@Observable, @MainActor), detail views
├── PlacePicker/                  # municipality search
├── Platform/                     # LocationProvider (CoreLocation), FileResultCache, PlaceSelectionStore
└── Resources/                    # Localizable.xcstrings (fi, sv, en), Assets
RevontuletUITests/                # main flows with stubbed HTTP + fixed location

Packages/AuroraCore/              # portable core, no Apple-only imports
├── Package.swift
├── Sources/AuroraCore/
│   ├── Model/                    # Station, Municipality, Place, Chance, AuroraResult, ...
│   ├── FMI/                      # request builders, BsWfs simple parser, HTTPClient, URLSessionHTTPClient
│   ├── Activity/                 # RIndex, ActivityClassifier, StationSelector
│   ├── Sky/                      # SolarPosition, cloud selection
│   ├── Chance/                   # ChanceCalculator
│   ├── Places/                   # PlaceResolver, geometry (haversine, point-in-polygon)
│   ├── AuroraService.swift
│   └── Resources/                # stations.json, municipalities data
└── Tests/AuroraCoreTests/
    └── Fixtures/                 # recorded FMI responses + reference R values

tools/
├── build-municipalities.py       # Statistics Finland WFS → bundled municipality file
└── record-fixtures.py            # dev-only: records open data + FMI reference R for tests
```

**Structure Decision**: One Xcode project with an iOS app target that depends on the local
`AuroraCore` Swift package. The package is the shared core required by Principle III and is the
unit a future Android app would reuse; the app target holds only UI and platform services. Data
tools are Python scripts outside the app because they run only at development time.

## Complexity Tracking

No constitution violations to justify.
