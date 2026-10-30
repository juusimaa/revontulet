---

description: "Task list for 003 Aurora Outlook"
---

# Tasks: Aurora Outlook

**Input**: Design documents from `/specs/003-aurora-outlook/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included. Constitution Principle IV (Test-First) applies, and every rule has reference
cases in contracts/ (chance v2 1–22, soon 1–12, outlook 1–10). Within each story, write the tests
first and check that they fail before you implement.

**Organization**: Tasks are grouped by user story. US1 (moon) can ship on its own. US2 (soon) and
US3 (outlook) build on the Foundational phase. US3 also uses US1's moon and chance-rules v2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1 = moon, US2 = soon, US3 = outlook

## Path Conventions

- Core: `Packages/AuroraCore/Sources/AuroraCore/`, tests in `Packages/AuroraCore/Tests/AuroraCoreTests/`
- App: `Revontulet/`, UI tests in `RevontuletUITests/`, unit tests in `RevontuletTests/`
- Alert service: `Server/`
- Scripts: `tools/` (Python 3 standard library only, like the existing scripts)
- Core run: `(cd Packages/AuroraCore && swift test)`. Linux run: see quickstart.md §1.
- UI-test launch arguments follow the existing `-uiTest…` convention in
  `Revontulet/App/RevontuletApp.swift`. quickstart.md's `-uitest-outlook <scenario>` is written
  here as `-uiTestOutlook <scenario>` (T080 updates quickstart.md).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Recorded test data

- [X] T001 [P] Write `tools/record-outlook-fixtures.py` (R10). It records into
  `Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/`:
  - `solar-wind-quiet.json`, `solar-wind-active.json` and `solar-wind-gaps.json` (with nulls) from
    `https://services.swpc.noaa.gov/products/geospace/propagated-solar-wind-1-hour.json`
  - `kp-forecast.json` (object shape) from `…/products/noaa-planetary-k-index-forecast.json`, plus
    a hand-made `kp-forecast-old-shape.json` (array of arrays with a header row)
  - `alerts.json` from `…/products/alerts.json`, kept or trimmed so that it holds a WATA20 (G1)
    watch, a WATA30 (G2) watch and a `CANCEL WATCH:` message
  - `cloud-forecast.xml`: the FMI `fmi::forecast::edited::weather::scandinavia::point::simple`
    query with all ten station positions from `Sources/AuroraCore/Resources/stations.json`,
    `parameters=TotalCloudCover&timestep=60`
  - `noaa-404.txt` and `noaa-malformed.json`

  Use only the Python standard library and follow `tools/record-fixtures.py`'s style.
- [X] T002 [P] Write `tools/record-moon-reference.py` (R4). It queries JPL Horizons (observer
  table, topocentric, airless apparent altitude, illuminated fraction) for at least 20 times at
  Kevo (KEV), Oulujärvi (OUJ) and Tartu (TAR). The times must include moonrise and moonset,
  polar night, a new moon and a full moon. It writes
  `Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/moon-reference.json` as
  `[{latitude, longitude, time (ISO UTC), altitude, illuminatedFraction}]`.
- [X] T003 Run T001 and T002 once and commit the fixtures in
  `Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/`. Check that `Package.swift` still
  copies `Fixtures` (it uses `.copy("Fixtures")`, so subfolders are included) and that
  `Fixtures.data("outlook/kp-forecast.json")` resolves in
  `Tests/AuroraCoreTests/Support/Fixtures.swift`; extend that helper if it does not handle subfolders.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Bands, NOAA URLs, the `OutlookService` shell with its cache, and the app wiring
that US2 and US3 extend. US1 does not need this phase.

**⚠️ CRITICAL**: US2 and US3 cannot start until this phase is complete.

- [ ] T004 [P] Write `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/BandTests.swift`:
  `Band.of(zoneID:)` gives North for KEV, KIL, IVA, MUO and PEL; Central for RAN, OUJ, MEK and
  HAN; South for TAR; and nil for an unknown code. Check that every station in `stations.json`
  has a band.
- [ ] T005 [P] Write `Packages/AuroraCore/Tests/AuroraCoreTests/NOAARequestsTests.swift`: the
  three URLs are exactly the ones in contracts/noaa-data.md and have no query items (FR-018).
- [ ] T006 [P] Write `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/OutlookServiceTests.swift`
  (shell only):
  - `cachedSnapshot()` makes no HTTP call (`StubHTTPClient` records calls).
  - `refresh(for:zoneID:at:force:)` never throws, even when every request fails.
  - The returned snapshot carries the place and is saved to an `InMemoryOutlookCache`.
  - A snapshot round-trips through `JSONEncoder`/`JSONDecoder`.
- [ ] T007 [P] Create `Packages/AuroraCore/Sources/AuroraCore/Outlook/Band.swift`: `public enum
  Band: String, Sendable, Hashable, Codable, CaseIterable { case north, central, south }` with
  `static func of(zoneID: String) -> Band?`, mapped as in contracts/soon-rules.md#bands.
- [ ] T008 [P] Create `Packages/AuroraCore/Sources/AuroraCore/NOAA/NOAARequests.swift`:
  `public enum NOAARequests` with the fixed URLs `propagatedSolarWind`, `kpForecast` and `alerts`
  (contracts/noaa-data.md).
- [ ] T009 Create `Packages/AuroraCore/Sources/AuroraCore/Outlook/OutlookModels.swift` with
  `public struct OutlookSnapshot: Sendable, Hashable, Codable`. It starts with `place: Place`
  only; US2 and US3 add their fields (data-model.md "Service and cache").
- [ ] T010 Create `Packages/AuroraCore/Sources/AuroraCore/Outlook/OutlookService.swift`:
  - `public protocol OutlookCache: Sendable` with `load()` and `save(_:)`, plus `public actor
    InMemoryOutlookCache`.
  - `public actor OutlookService` with `init(http:cache:)`, `cachedSnapshot()` and
    `refresh(for:zoneID:at:force:)` (contracts/aurora-core-outlook-api.md).
  - Due-time bookkeeping per input (research R8 table: solar wind 5 min, Kp forecast 60 min,
    alerts 60 min, cloud forecast 3 h; `force` fetches all). A failed fetch keeps the last inputs
    and is retried on the next refresh, never in a loop.

  Make T004–T006 pass.
- [ ] T011 Create `Revontulet/Platform/FileOutlookCache.swift`, modelled on
  `Revontulet/Platform/FileResultCache.swift`. It stores `OutlookSnapshot` in its own file in
  Application Support, separate from the headline cache; an undecodable file loads as nil. Honour
  `-uiTestResetCache` as `FileResultCache` does, where `Revontulet/App/RevontuletApp.swift` wires it.
- [ ] T012 Wire `OutlookService` into `Revontulet/MainScreen/MainScreenModel.swift` and
  `Revontulet/App/RevontuletApp.swift`:
  - Create it with the same `HTTPClient` as `AuroraService` and a `FileOutlookCache`.
  - Load `cachedSnapshot()` at launch, next to the cached headline.
  - Run `refresh` concurrently with the headline refresh on the same triggers (launch,
    foreground, the 5-minute timer, pull to refresh), using the injected `now` clock. Never await
    one before showing the other.
  - Expose `outlookSnapshot`, set only when its place matches the current place.
  - Hide it when location is denied or the place is outside coverage (contracts/main-screen-additions.md
    States).

**Checkpoint**: Foundation ready. Core tests pass on macOS. The app builds and behaves exactly as
before.

---

## Phase 3: User Story 1 - Moonlight is part of the chance to see (Priority: P1) 🎯 MVP

**Goal**: The moon is computed on the device, and a bright moon is one "sky brightness" step in
the chance rules (v2). The headline, the alert service's zone evaluation and the details all use
it.

**Independent Test**: The chance-rules v2 reference cases 1–22 and the moon reference values
pass (SC-001, SC-002). In the app, `-uiTestOutlook moon` shows "Moderate – bright moon" with the
moon up in the details.

### Tests for User Story 1 ⚠️ write first, check that they fail

- [X] T013 [P] [US1] Write `Packages/AuroraCore/Tests/AuroraCoreTests/MoonPositionTests.swift`:
  - For every entry in `Fixtures/outlook/moon-reference.json` (at least 20),
    `MoonPosition.state(latitude:longitude:at:)` must be within 1° in `altitude` and within 0.02 in
    `illuminatedFraction` (SC-002).
  - `isBright == (altitude > 0 && illuminatedFraction >= 0.5)`.
  - Phase names on the 2026 new and full moon dates (2026-11-09 new, 2026-11-24 full) and one
    quarter.
- [X] T014 [P] [US1] Update `Packages/AuroraCore/Tests/AuroraCoreTests/ChanceCalculatorTests.swift`
  for chance-rules v2 (contracts/chance-rules.md):
  - Cases 1–12 with `moonBright: false`.
  - New cases 13–22 with level, limiting factor and reason (case 21 has `cloudsIncluded ==
    false`).
  - A property test over all inputs: twilight together with a bright moon lowers the level by at
    most one step.

  Update the calls in `AuroraServiceTests.swift:41` and `Alerts/AlertPolicyTests.swift` to the new
  signature.
- [X] T015 [P] [US1] Update `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/ZoneEvaluatorTests.swift`:
  - The zone chance uses the moon at the zone's representative position.
  - A Probable zone with a dark sky, a clear sky and a bright moon gives Moderate with reason
    `brightMoon`.

  In `Alerts/AlertMessageTests.swift`, with `moonKeys: true`, Moderate/brightMoon maps to
  `alert.body.brightMoon`, and with unknown clouds to `alert.body.brightMoon.cloudsUnknown`. With
  `moonKeys: false`, the same cases map to `alert.body.twilight` and
  `alert.body.twilight.cloudsUnknown`. Both new keys are in `bodyKeys`.
- [X] T016 [P] [US1] Update `Packages/AuroraCore/Tests/AuroraCoreTests/AuroraResultCodingTests.swift`
  and `AuroraServiceCachingTests.swift`:
  - `AuroraResult.moon` round-trips.
  - A v1 cached result without `moon` fails to decode, and the service treats the cache as empty.
  - `AuroraService.refresh` fills `moon` for the place and passes `moonBright` to the rules.

### Implementation for User Story 1

- [X] T017 [US1] Refactor `Packages/AuroraCore/Sources/AuroraCore/Sky/SolarPosition.swift`.
  Expose, as internal helpers, the Julian date/centuries, the sun's apparent ecliptic longitude,
  the mean obliquity, the equatorial-to-horizontal conversion and the local sidereal time, so the
  moon can reuse them (R4). `SolarPositionTests` must still pass unchanged.
- [X] T018 [US1] Create `Packages/AuroraCore/Sources/AuroraCore/Sky/MoonPosition.swift` (Meeus,
  2nd ed.; formulas only, no copied code):
  - `public enum MoonPosition` with `state(latitude:longitude:at:) -> MoonState`.
  - Geocentric longitude, latitude and distance from ch. 47 with the largest periodic terms;
    equatorial coordinates and hour angle.
  - Topocentric altitude with parallax (`alt_topo = alt_geo − asin(sin(π)·cos(alt_geo))`), no
    refraction.
  - Illuminated fraction from the sun–moon elongation (ch. 48).
  - `public struct MoonState: Sendable, Hashable, Codable { altitude, illuminatedFraction, phase,
    isBright }` with `isBright = altitude > 0 && illuminatedFraction >= 0.5`.
  - `public enum MoonPhase: String, …, CaseIterable` with `new, waxingCrescent, firstQuarter,
    waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent`. Each covers 1/8 of the cycle
    centred on its nominal phase. Add `key` = `moon.phase.<case>`.

  Foundation only (Linux). Make T013 pass.
- [X] T019 [US1] Add `case moon` to `LimitingFactor` in
  `Packages/AuroraCore/Sources/AuroraCore/Model/Levels.swift`, and `case brightMoon` to
  `ChanceReason` in `Packages/AuroraCore/Sources/AuroraCore/Chance/ChanceCalculator.swift`.
- [X] T020 [US1] Implement chance-rules v2 in
  `Packages/AuroraCore/Sources/AuroraCore/Chance/ChanceCalculator.swift`:
  - Replace `chance(activity:darkness:clouds:)` with `chance(activity:darkness:moonBright:clouds:)`;
    remove the v1 signature.
  - Step 4: twilight or a bright moon lowers the level by one, never two. The limiting factor is
    `.twilight` if there is twilight, otherwise `.moon`.
  - `reason(for:activity:clouds:)` maps `.moon` → `.brightMoon`.

  Make T014 pass.
- [X] T021 [US1] Add `public let moon: MoonState` to `AuroraResult` in
  `Packages/AuroraCore/Sources/AuroraCore/Model/Result.swift`. In
  `Packages/AuroraCore/Sources/AuroraCore/AuroraService.swift`, compute
  `MoonPosition.state` for the place at the result time and pass `moon.isBright` to
  `ChanceCalculator.chance`. Make T016 pass.
- [X] T022 [US1] In `Packages/AuroraCore/Sources/AuroraCore/Alerts/ZoneEvaluator.swift`, compute
  the moon at each zone's representative position and the evaluation time, and pass `moonBright`.
- [X] T023 [US1] In `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertMessage.swift`, change
  `make(for:)` to `make(for:moonKeys: Bool)` (research R9):
  - `moonKeys == true`: `(.moderate, .brightMoon)` → `alert.body.brightMoon`.
  - `moonKeys == false`: `(.moderate, .brightMoon)` → `alert.body.twilight`, because 2.0 has
    no moon keys.
  - Both use the existing `.cloudsUnknown` suffix logic.

  Add `alert.body.brightMoon` and `alert.body.brightMoon.cloudsUnknown` to `bodyKeys` (and so to
  `allKeys`). Make T015 pass.
- [X] T024 [US1] Add the `ALERT_MOON_KEYS` setting to the alert service (R9):
  - Read it in `Server/Sources/AlertServer/Configuration.swift` as a boolean, `false` when unset;
    any value other than `true`/`false` is `.invalid`.
  - Pass it to `AlertMessage.make(for:moonKeys:)` in `Server/Sources/AlertServer/Dispatcher.swift`.
  - Document it in `Server/deploy/alerts.env.example`: "Set to true 30 days after 3.0 is in the
    App Store".
  - Test the parsing in `Server/Tests/AlertServerTests/ConfigurationTests.swift`, and that the
    dispatcher sends the twilight key for a moon case when the setting is off, in
    `DispatcherTests.swift`.
- [X] T025 [P] [US1] Add to `Revontulet/Resources/Localizable.xcstrings` (fi, sv, en):
  `reason.brightMoon`, the eight `moon.phase.*` names, the moon detail lines ("Moon %d %%, %@,
  up" / "below the horizon") and a VoiceOver label. Also add `alert.body.brightMoon` ("Strong
  activity near %@, but the moon is bright.") and `alert.body.brightMoon.cloudsUnknown` ("Strong
  activity near %@ under a bright moon. Cloud cover is unknown."), so that
  `RevontuletTests/AlertStringsTests.swift` finds them.
- [X] T026 [US1] In `Revontulet/MainScreen/CoreLabels.swift`, add labels for
  `LimitingFactor.moon`, `ChanceReason.brightMoon` and `MoonPhase`.
- [X] T027 [US1] In `Revontulet/MainScreen/ChanceDetailsView.swift`, add a moon row next to
  darkness showing illuminated percent, phase name and up/below the horizon (FR-004). It must
  work with Dynamic Type and VoiceOver.
- [X] T028 [US1] Add a `-uiTestOutlook moon` scenario in `Revontulet/App/RevontuletApp.swift` and
  `Revontulet/App/UITestHTTPClient.swift`. Use `-uiTestStrongActivity` (Probable), a dark clear
  sky and a fixed `-uiTestTime` with a bright moon at the test location (e.g. 2026-11-24T21:00:00Z
  at Oulu). Check the date against `MoonPosition`.
- [X] T029 [US1] Create `RevontuletUITests/OutlookUITests.swift` with the moon test: the headline
  shows "Moderate – bright moon" and the details show the moon as up.
- [X] T030 [US1] Run the core tests and `cd Server && swift test`. `ZoneEvaluator` changes reach
  the alert service through the core; the only server source change is T024. Fix any server test
  that hard-codes a v1 chance.

**Checkpoint**: US1 is complete and shippable: the headline, the alerts and the details include
the moon.

---

## Phase 4: User Story 2 - Know whether activity is about to rise (Priority: P2)

**Goal**: A "Soon" line under the headline, from the median dawn–dusk electric field over 20
minutes of SWPC's propagated solar wind, per band, with SWPC's arrival time. It never changes
the headline.

**Independent Test**: Soon reference cases 1–12 pass. `SoonReplayTests` meet SC-003. In the
app, `-uiTestOutlook storm` shows the soon line, `quiet` shows none, and `noaa-down` hides it and
leaves the headline unchanged.

### Calibration (R6, before the thresholds are final)

- [ ] T031 [US2] Write `tools/calibrate-soon.py` (R6):
  - Load NASA OMNI 1-minute data (offline download, public domain) and FMI magnetometer archives
    for at least 20 nights where a Lapland station reached Probable and 20 quiet nights,
    2024–2026.
  - Compute R with the core's method (as in `tools/alert-reference.py`) and Ey = `speed ×
    max(0, −Bz) / 1000`.
  - Search the `possible`/`likely` threshold pairs per band that meet SC-003 with the fewest false
    Likely hours.
  - Write the chosen nights to `Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/soon-nights/`.
- [ ] T032 [US2] Run T031. Replace the initial thresholds in
  `specs/003-aurora-outlook/contracts/soon-rules.md` (Thresholds table) with the calibrated
  values, and record the nights used and the result in `specs/003-aurora-outlook/research.md` R6.
  Recompute the soon-rules reference cases that depend on the thresholds (8–10, and any other
  case whose expected state changes) so that each still tests what it describes, and use the new
  values in T034.

### Tests for User Story 2 ⚠️ write first, check that they fail

- [ ] T033 [P] [US2] Write `Packages/AuroraCore/Tests/AuroraCoreTests/NOAAParserTests.swift`
  (solar wind part), using the `Fixtures/outlook/solar-wind-*.json` files:
  - Columns are found by name.
  - `null` → nil; rows without `time_tag` are dropped; duplicate minutes keep the last row; the
    result is sorted by time.
  - A header without `time_tag`, `bz`, `speed` or `propagated_time_tag` throws.
  - `noaa-404.txt` and `noaa-malformed.json` throw.
- [ ] T034 [P] [US2] Write `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/SoonCalculatorTests.swift`:
  - All twelve reference cases in contracts/soon-rules.md, with state, driver and
    `arrivalMinutes`.
  - The main-screen visibility rule (FR-010): the line is hidden only when it is too light both
    now and at now + `arrivalMinutes` at the place; it is shown on an overcast night.
- [ ] T035 [P] [US2] Write `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/SoonReplayTests.swift`
  using `Fixtures/outlook/soon-nights/`:
  - In ≥ 70% of the storm nights, the state is Possible or Likely ≥ 15 min before the station
    reached Probable.
  - On the quiet nights, Likely covers ≤ 10% of the dark hours (SC-003).

  Use `Support/NightReplay.swift` where it fits.
- [ ] T036 [P] [US2] Extend `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/OutlookServiceTests.swift`
  for solar wind:
  - Fetched at most every 5 min unless `force`.
  - A failed fetch keeps the last samples.
  - The state becomes `unknown` once the newest sample is > 20 min old.
  - Hysteresis uses the previous snapshot's state only for the same place.
  - A solar wind failure leaves the other snapshot fields untouched.

### Implementation for User Story 2

- [ ] T037 [US2] Add to `Packages/AuroraCore/Sources/AuroraCore/Outlook/OutlookModels.swift`:
  - `SolarWindSample { time: Date, arrival: Date?, bz: Double?, speed: Double?, density: Double? }`
  - `SoonState { quiet, possible, likely, unknown }`, ordered quiet < possible < likely for
    hysteresis
  - `SoonSignal { state, driver: Double?, arrivalMinutes: Int?, latest: SolarWindSample?,
    dataTime: Date?, showsOnMainScreen: Bool }`

  Add `soon: SoonSignal` and the raw `samples` with their fetch time to `OutlookSnapshot`
  (data-model.md).
- [ ] T038 [US2] Create `Packages/AuroraCore/Sources/AuroraCore/NOAA/NOAAParser.swift` with
  `static func propagatedSolarWind(_ data: Data) throws -> [SolarWindSample]` per
  contracts/noaa-data.md. Make T033 pass.
- [ ] T039 [US2] Create `Packages/AuroraCore/Sources/AuroraCore/Outlook/SoonCalculator.swift`:
  - `public enum SoonCalculator` with `signal(samples:band:now:previous:) -> SoonSignal`,
    following contracts/soon-rules.md steps 1–7.
  - A 20-minute window ending at the newest sample with Bz and speed.
  - Unknown if that sample is > 20 min old or < 15 of 20 minutes are valid.
  - Median Ey.
  - Band thresholds from T032.
  - Hysteresis at 75% of the previous state's threshold.
  - The arrival of the first window minute that meets the threshold, rounded to the nearest 15 min,
    minimum 15.

  Add `showsOnMainScreen(_:at:now:)`, which uses `SolarPosition` darkness now and at now +
  `arrivalMinutes` (FR-010). Only `OutlookService` calls it (T040), so no calculation runs on the
  main actor (Principle V). Make T034 and T035 pass.
- [ ] T040 [US2] In `Packages/AuroraCore/Sources/AuroraCore/Outlook/OutlookService.swift`, fetch
  `NOAARequests.propagatedSolarWind` when due, parse it, keep the last good samples on failure,
  compute `SoonCalculator.signal` with `Band.of(zoneID:)` and the previous snapshot's state for
  the same place, set `showsOnMainScreen` from `SoonCalculator.showsOnMainScreen`, and store the
  result in the snapshot. Recompute both on every refresh, also from cached samples. Make T036
  pass.
- [ ] T041 [P] [US2] Add to `Revontulet/Resources/Localizable.xcstrings` (fi, sv, en):
  - The "Soon" label.
  - "Activity likely to rise %@", "Activity may rise %@", and for a headline activity of
    Probable: "Activity likely to continue" (Likely) and "Activity may stay high" (Possible).
  - "within about %d minutes" and "within about an hour".
  - The "overcast now" note.
  - Details: "No sign of rising activity", "No sign of further rise", "Solar wind data
    unavailable" with age, and Bz/speed/density labels with units.
  - VoiceOver "Forecast: %@".
- [ ] T042 [US2] In `Revontulet/MainScreen/CoreLabels.swift`, add labels for `SoonState` and the
  arrival window (15/30/45 → minutes, ≥ 60 → "about an hour"). Choose the variant text for
  Likely and Possible when the headline activity is Probable (contracts/soon-rules.md Display).
- [ ] T043 [US2] In `Revontulet/MainScreen/MainScreenView.swift`, add the soon line directly under
  the headline, visibly secondary and labelled as a forecast (Principle VI; use the
  `ios-ui-craft` skill). Show it only for Possible or Likely when `soon.showsOnMainScreen` is true
  (read from the snapshot; the view does no calculation), with the overcast note when the headline is None
  because of overcast. It must never use the headline's level styling at that size (FR-009).
- [ ] T044 [US2] In `Revontulet/MainScreen/ChanceDetailsView.swift`, add a solar wind section:
  state text, Bz, speed, density and data age; "unavailable" with the last data age when Unknown
  (FR-010, FR-020).
- [ ] T045 [US2] In `Revontulet/App/UITestHTTPClient.swift`, serve
  `services.swpc.noaa.gov/products/geospace/propagated-solar-wind-1-hour.json` for
  `-uiTestOutlook storm` (Ey ≥ the North `likely` threshold), `quiet` (Bz northward) and
  `noaa-down` (HTTP 500). Shift the times to the test clock so the newest sample is about 8 min
  old. Today the client returns 400 for any non-FMI URL; keep that for unknown URLs.
- [ ] T046 [US2] Add tests to `RevontuletUITests/OutlookUITests.swift`:
  - storm → the soon line "Activity likely to rise …" with an unchanged headline.
  - quiet → no soon line, and the details say "No sign of rising activity".
  - noaa-down → no soon line, the headline as usual, and the details say "Solar wind data
    unavailable".

**Checkpoint**: US1 and US2 work independently. A NOAA failure affects only the soon line.

---

## Phase 5: User Story 3 - Plan for tonight and tomorrow night (Priority: P3)

**Goal**: An outlook for tonight and tomorrow night. It combines the Kp forecast, storm watches,
one shared FMI cloud forecast, darkness and the moon through chance-rules v2.

**Independent Test**: Outlook reference cases 1–11 pass, and `KpMappingTests` meet SC-004. In
the app, `-uiTestOutlook storm` shows "Tonight: High – geomagnetic storm watch", `summer` shows
"None – too light" for both nights, and `noaa-down` shows "Outlook unavailable".

**Depends on**: US1 (T018 `MoonPosition`, T020 chance-rules v2).

### Calibration (R7, before the thresholds are final)

- [ ] T047 [US3] Write `tools/calibrate-kp.py` (R7):
  - Load GFZ definitive Kp (offline download, CC BY 4.0, credited in the script header) and FMI
    magnetometer archives for at least 30 nights across all bands, 2024–2026.
  - For each night, compare the band mapping of the observed Kp over the dark hours with the
    highest FMI activity level at each zone's station.
  - Search the `Possible from`/`Probable from` thresholds per band that maximise agreement
    (SC-004 needs ≥ 80%).
  - Write the nights to `Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/kp-nights.json`.
- [ ] T048 [US3] Run T047. Replace the initial values in
  `specs/003-aurora-outlook/contracts/outlook-rules.md` §2 (thresholds table) with the calibrated
  values, and record the result in `specs/003-aurora-outlook/research.md` R7. Recompute the
  outlook-rules reference cases that depend on the thresholds (1–3, 5 and 11) so that each still
  reaches its intended level, and use the new values in T051.

### Tests for User Story 3 ⚠️ write first, check that they fail

- [ ] T049 [P] [US3] Extend `Packages/AuroraCore/Tests/AuroraCoreTests/NOAAParserTests.swift`.

  Kp forecast:
  - The object shape (`kp-forecast.json`) and the old shape (`kp-forecast-old-shape.json`) give
    the same blocks.
  - `time_tag` without `Z` is UTC.
  - An unknown `observed` value → `.predicted`.

  Storm watches from `alerts.json`:
  - G1 and G2 levels are read from the day lines, not the code.
  - The issue time comes from `Issue Time:`, falling back to `issue_datetime`.
  - The newest watch supersedes older ones, and a later `CANCEL WATCH:` removes its days.
  - `None` days and days before today (UTC) are dropped.
  - Year rollover (a December issue with January days).
  - A WATA message that matches no pattern is skipped without failing the file.
  - Malformed JSON throws.
- [ ] T050 [P] [US3] Write `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/NightsTests.swift`
  (contracts/outlook-rules.md §1):
  - Tonight while dark (the period under way, with relevant hours from now).
  - Tonight in the afternoon (the next dark period within 24 h).
  - Tomorrow night after tonight ends.
  - KEV on 2026-06-21 is too light for both nights.
  - Polar night at KEV in December: the period is capped at 24 h.
  - Relevant hours are the Dark hours when there are any, otherwise all twilight hours.
  - The DST change nights 2026-10-24/25 and 2026-03-28/29 in Europe/Helsinki.
- [ ] T051 [P] [US3] Write `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/OutlookCalculatorTests.swift`:
  - All eleven reference cases in contracts/outlook-rules.md (OUJ, band Central, synthetic Kp
    blocks and cloud forecasts). Case 11: a watch covers the night that starts on its date in
    Europe/Helsinki, not the early hours of the night before.
  - The display reason (`stormWatch` replaces "some activity" or "good conditions" only when the
    watch decided the activity).
  - The cloud mean → octas → condition, with Unknown when fewer than half of the relevant hours
    have a value.
  - Moon bright for at least half of the relevant hours.
  - `kpFetchedAt` and `cloudsFetchedAt` are carried.
- [ ] T052 [P] [US3] Write `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/KpMappingTests.swift`:
  apply the band mapping to the observed Kp in `Fixtures/outlook/kp-nights.json` and expect at
  least 80% agreement over at least 30 nights (SC-004).
- [ ] T053 [P] [US3] Extend `Packages/AuroraCore/Tests/AuroraCoreTests/FMIRequestTests.swift` and
  `BsWfsParserTests.swift`:
  - `FMIRequests.cloudForecast(zones:)` has all ten `latlon` items from `stations.json`,
    `parameters=TotalCloudCover`, `timestep=60` and nothing user-derived.
  - Parsing `Fixtures/outlook/cloud-forecast.xml` gives one `CloudForecast` per zone, matched to
    the nearest zone position within 1 km, with `NaN` → missing.
- [ ] T054 [P] [US3] Extend `Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/OutlookServiceTests.swift`:
  - The Kp forecast and alerts are fetched at most every 60 min, and the cloud forecast at most
    every 3 h.
  - Each fetch fails on its own (a Kp failure leaves the soon signal and the clouds intact).
  - With every request failing, a cached snapshot is recomputed for a new time and another place
    from its raw inputs (offline).
  - The outlook is unavailable when no Kp block covers tonight.

### Implementation for User Story 3

- [ ] T055 [US3] Add to `Packages/AuroraCore/Sources/AuroraCore/Outlook/OutlookModels.swift`, per
  data-model.md:
  - `KpKind { observed, estimated, predicted }`
  - `KpBlock { start, kp (0…9), kind }`, covering `start ..< start + 3 h`
  - `KpForecast { blocks (sorted by start), fetchedAt }`
  - `StormWatch { level (G 1…5), days ([String] "yyyy-MM-dd" UTC), issuedAt }`
  - `CloudForecast { zoneID, hourly: [Date: Double] (%, UTC hours), fetchedAt }`
  - `Night { start, end, relevantStart, relevantEnd: Date?, reachesDark }`
  - `NightKind { tonight, tomorrow }` and `OutlookAvailability { available, tooLight, unavailable }`
  - `OutlookReason` (a `ChanceReason` or `stormWatch`; key `outlook.reason.stormWatch`)
  - `NightOutlook` with all fields in data-model.md, and `Outlook { tonight, tomorrow, computedAt }`

  Add `outlook: Outlook?`, `forecast`, `watches` and `clouds` (with fetch times) to `OutlookSnapshot`.
- [ ] T056 [US3] In `Packages/AuroraCore/Sources/AuroraCore/NOAA/NOAAParser.swift`, add
  `kpForecast(_:)` (both shapes) and `stormWatches(_:now:)` per contracts/noaa-data.md
  "Storm watches", steps 1–5. Make T049 pass.
- [ ] T057 [US3] Add `public static func cloudForecast(zones: [AlertZone]) -> URL` (one request, a
  repeated `latlon`) to `Packages/AuroraCore/Sources/AuroraCore/FMI/FMIRequests.swift`. Add
  parsing to `[CloudForecast]` in `Packages/AuroraCore/Sources/AuroraCore/FMI/BsWfsParser.swift`
  (nearest zone within 1 km, `NaN` → missing). Make T053 pass.
- [ ] T058 [US3] Create `Packages/AuroraCore/Sources/AuroraCore/Outlook/Nights.swift`: find dark
  periods by sampling `SolarPosition` darkness every 5 min (not Too light = sun ≤ −6°), with
  tonight, tomorrow, a 24 h cap and relevant hours (contracts/outlook-rules.md §1). Make T050 pass.
- [ ] T059 [US3] Create `Packages/AuroraCore/Sources/AuroraCore/Outlook/OutlookCalculator.swift`
  with `public enum OutlookCalculator` and `outlook(place:band:now:kp:watches:clouds:) -> Outlook`:
  - §2 expected activity: the max Kp over blocks overlapping the relevant hours; watch Kp = 4 +
    G for watches whose day is the night's local start date (Europe/Helsinki); take the higher;
    band thresholds from T048.
  - §3 sky: darkness, the moon via `MoonPosition` sampled every 5 min, cloud mean.
  - §4 level via `ChanceCalculator.chance(activity:darkness:moonBright:clouds:)`, Too light
    without any forecast, unavailable when expected activity is unknown, and the storm-watch
    reason.

  Keep it well under 50 ms on a device. Make T051 and T052 pass.
- [ ] T060 [US3] In `Packages/AuroraCore/Sources/AuroraCore/Outlook/OutlookService.swift`:
  - Fetch `NOAARequests.kpForecast`, `NOAARequests.alerts` and
    `FMIRequests.cloudForecast(zones:)` when due, each keeping its last good input on failure.
  - On every refresh, recompute the outlook from the cached inputs for the place and date, so
    "tonight" moves on at the end of a dark period without a fetch.

  Make T054 pass.
- [ ] T061 [P] [US3] Add to `Revontulet/Resources/Localizable.xcstrings` (fi, sv, en):
  - The "Forecast" heading, "Tonight" and "Tomorrow night".
  - The row format "%@ – %@" and `outlook.reason.stormWatch` ("geomagnetic storm watch").
  - G1–G5 in plain language.
  - "Outlook unavailable" with the age of the last forecast.
  - Details: expected activity, max Kp, darkness, moon, mean cloud cover, "updated %@", "This is
    a forecast, not a measurement" and "cloud cover not included".
  - VoiceOver "Forecast for tonight: %@" and "Forecast for tomorrow night: %@".
- [ ] T062 [US3] In `Revontulet/MainScreen/CoreLabels.swift`, add labels for `NightKind`,
  `OutlookAvailability`, `OutlookReason` and G levels.
- [ ] T063 [US3] Create `Revontulet/MainScreen/OutlookSectionView.swift`: two rows under a
  "Forecast" heading, or one "Outlook unavailable" row when both nights are unavailable. Levels
  are text, not colour alone, and the styling is visibly secondary to the headline. Tapping
  opens the outlook details. Use the `ios-ui-craft` skill.
- [ ] T064 [US3] In `Revontulet/MainScreen/MainScreenView.swift`, place `OutlookSectionView`
  below the headline block. Show it whenever the place is inside coverage, including when the
  headline has no data. Hide it for location denied or outside coverage.
- [ ] T065 [US3] Add the outlook details (per night: expected activity, max Kp, storm watch
  level, darkness, moon, mean cloud cover, Kp and cloud update times, "This is a forecast, not a
  measurement") in `Revontulet/MainScreen/ChanceDetailsView.swift`, or in a sheet that
  `OutlookSectionView` opens (FR-016).
- [ ] T066 [US3] In `Revontulet/App/UITestHTTPClient.swift`, add stubs for the Kp forecast,
  `alerts.json` and the FMI cloud forecast (`storedquery_id`
  `fmi::forecast::edited::weather::scandinavia::point::simple`), shifted to the test clock:
  - storm: Kp 3, a G2 watch for the UTC day and clear clouds
  - summer: run with `-uiTestTime 2026-06-21T12:00:00Z`
  - noaa-down: every NOAA URL returns 500
- [ ] T067 [US3] Add tests to `RevontuletUITests/OutlookUITests.swift`:
  - storm → "Tonight: High – geomagnetic storm watch".
  - summer → "None – too light" for both nights.
  - noaa-down → "Outlook unavailable" with the headline unaffected.
  - Offline relaunch (`-uiTestOffline` after a stubbed run) → the outlook from cache.

**Checkpoint**: All three stories work independently and together.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T068 [P] Add "NOAA Space Weather Prediction Center" to the attribution in
  `Revontulet/MainScreen/ChanceDetailsView.swift`, next to FMI and Statistics Finland, with no
  logo (FR-021). Add the string in fi, sv and en.
- [ ] T069 [P] Update `docs/privacy.md` (FR-022): the app contacts `services.swpc.noaa.gov`; the
  requests carry nothing about the user and are identical for every user; the cloud forecast asks
  for all zones at once. Confirm that `Revontulet/Resources/PrivacyInfo.xcprivacy` needs no change
  (R12).
- [ ] T070 [P] Add a test to `Server/Tests/AlertServerTests/EvaluationLoopTests.swift`: the stub
  HTTP client fails the test on any request to `services.swpc.noaa.gov` (FR-025). Then run `cd
  Server && swift test`.
- [ ] T071 Deploy the alert service with the updated core, after T024 and T070:
  - Tag `alerts-0.3.0` so that the `alert-service` workflow builds the image.
  - Deploy to `/opt/revontulet-alerts` with `ALERT_MOON_KEYS=false` in its env file.
  - Check the logs for one evaluation cycle: no NOAA requests, and zone results include the moon.
  - Note the switch to `ALERT_MOON_KEYS=true` (30 days after 3.0 is in the App Store) in the
    release PR description.
- [ ] T072 Run `tools/check-core-portability.sh` and the Linux core tests (`docker run --rm -v
  "$PWD":/src -w /src/Packages/AuroraCore swift:6.4.1-noble swift test`). Fix any Apple-only API
  in `MoonPosition`, `NOAAParser` or `OutlookService`.
- [ ] T073 Resolve the R2 open point: add a `--compare-kp` mode to
  `tools/record-outlook-fixtures.py`. It fetches the JSON Kp forecast and
  `text/3-day-forecast.txt` and logs both predicted blocks to a scratch CSV. Run it over a few days
  before release, then record the finding in `specs/003-aurora-outlook/research.md` R2. Revisit the
  plan if the two keep diverging.
- [ ] T074 Accessibility and visual pass with the `ios-ui-craft` skill on the soon line, the
  outlook section and the new details:
  - Dynamic Type up to AX5.
  - VoiceOver reads "Forecast: …" and "Forecast for tonight: …".
  - No meaning by colour alone.
  - The headline is still first and largest (SC-006).
  - Simulator screenshots in fi, sv and en.
- [ ] T075 Measure on device that the cached snapshot appears with the headline within 1 s
  (SC-008), and that `OutlookCalculator` plus `SoonCalculator` run in under 50 ms (plan
  performance goal).
- [ ] T076 Check that all new string keys exist in fi, sv and en in
  `Revontulet/Resources/Localizable.xcstrings` with no stale or missing entries, and run
  `RevontuletTests/AlertStringsTests` (quickstart.md §2).
- [ ] T077 Before the first TestFlight checkpoint, set `MARKETING_VERSION: "3.0"` in `project.yml`
  (the Xcode project is generated from it), then regenerate the project.
- [ ] T078 [P] Update `README.md` with the moon, soon and outlook features and the NOAA data
  source.
- [ ] T079 Run quickstart.md §1–§5 end to end, including the live device check in Oulu.
- [ ] T080 [P] Update `specs/003-aurora-outlook/quickstart.md`: change the scenario launch
  argument to `-uiTestOutlook <scenario>` and list the final suites.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: needs T003. Blocks US2 and US3. US1 does not need it.
- **US1 (Phase 3)**: needs T003 (moon reference). Can start in parallel with Phase 2.
- **US2 (Phase 4)**: needs Phase 2. T032 (thresholds) comes before T039.
- **US3 (Phase 5)**: needs Phase 2 and US1's T018 and T020. T048 (thresholds) comes before T059.
- **Polish (Phase 6)**: after the desired stories.

### Within Each User Story

- Tests are written first and fail; models come before parsers and calculators, then the
  service, then the app UI.
- Strings tasks marked [P] can run alongside the core tasks.
- UI tests come last in each story.

### Story completion order

`Setup → (US1 ∥ Foundational) → US2 → US3 → Polish`. This matches the plan's delivery order: P1
moon with the alert key fallback, the alert service deploy, calibration, P2 soon, P3 outlook,
then privacy and attribution.

---

## Parallel Examples

### Setup

```text
Task: "T001 tools/record-outlook-fixtures.py"
Task: "T002 tools/record-moon-reference.py"
```

### User Story 1 tests

```text
Task: "T013 MoonPositionTests.swift"
Task: "T014 ChanceCalculatorTests.swift v2 cases"
Task: "T015 ZoneEvaluatorTests.swift + AlertMessageTests.swift"
Task: "T016 AuroraResultCodingTests.swift + AuroraServiceCachingTests.swift"
```

### User Story 2 tests (after T032)

```text
Task: "T033 NOAAParserTests.swift solar wind"
Task: "T034 SoonCalculatorTests.swift"
Task: "T035 SoonReplayTests.swift"
Task: "T036 OutlookServiceTests.swift solar wind"
```

### User Story 3 tests (after T048)

```text
Task: "T049 NOAAParserTests.swift Kp + watches"
Task: "T050 NightsTests.swift"
Task: "T051 OutlookCalculatorTests.swift"
Task: "T052 KpMappingTests.swift"
Task: "T053 FMIRequestTests + BsWfsParserTests cloud forecast"
```

---

## Implementation Strategy

### MVP first (US1)

1. Phase 1.
2. Phase 3 (US1). Stop and validate: SC-001, SC-002, the moon UI test, and the server tests.
3. US1 is shippable on its own; it needs no network change.

### Incremental delivery

1. Setup, then US1 (moon), then a TestFlight checkpoint (version 3.0, T077) and the alert
   service deploy (T071).
2. Foundational, then US2 (soon), then validate SC-003 and the soon UI tests.
3. US3 (outlook), then validate SC-004 and the outlook UI tests.
4. Polish: privacy policy, attribution, portability, the R2 cross-check, then merge to `main`.

---

## Notes

- [P] tasks touch different files and have no dependencies on incomplete tasks.
- The spec's widgets and map (FR-005) have no targets in this repository today. They get the moon
  automatically through `ChanceCalculator` when they are added.
- Commit after each task or logical group, and run the build check per commit, push and
  checkpoint (release flow).
- No test touches the live network. Recording and calibration scripts run by hand only.
