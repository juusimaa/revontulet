# Implementation Plan: Aurora Outlook

**Branch**: `003-aurora-outlook` | **Date**: 2026-10-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-aurora-outlook/spec.md`

## Summary

FMI's R value stays the headline. Three additions sit around it, all in `AuroraCore`:

1. **Moon**: a Meeus-based moon position (topocentric altitude, illuminated fraction, phase)
   computed on the device. The chance rules gain one "sky brightness" step: twilight or a bright
   moon lowers the level by one, never two. The headline, the alert service's zone evaluation
   and the outlook all use the same rules. A new alert text for "Moderate – bright moon" has to
   ship in 2.0 before it reaches the App Store (R9).
2. **Soon**: SWPC's propagated solar wind for the last hour (2 KB). The median dawn–dusk electric
   field over 20 minutes gives Quiet, Possible or Likely per latitude band, and SWPC's modelled
   arrival time gives the window. It never changes the headline.
3. **Outlook**: tonight and tomorrow night from the SWPC Kp forecast and parsed storm watches,
   mapped per band to FMI's activity levels. They are combined with that night's darkness, the
   moon and one shared FMI cloud forecast request for all ten zones, using the same chance rules.

Research found that SWPC's legacy solar wind files are gone (SWFO-L1 transition), that the Kp
forecast JSON changed shape, and that watches exist only as text. The design therefore puts
every new input behind its own fetch and its own failure state in a separate `OutlookService`.
Alerts do not use the new signals (FR-025). See [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.1); Swift 6.4.1 on Linux for the core and the alert
service; Swift 6 language mode, strict concurrency.

**Primary Dependencies**: None new. Core: Foundation only (Linux-portable); the moon is
implemented from published formulas (R4). App: SwiftUI. Tools: Python 3 standard library, as
the existing `tools/` scripts.

**Storage**: App: a new `OutlookSnapshot` file in Application Support, separate from the
headline cache. `AuroraResult` gains `moon`; an old cache fails to decode and is treated as
empty once. No server storage change.

**Testing**: Swift Testing in `AuroraCore`: chance-rules v2 reference cases, moon against JPL
Horizons references, soon and outlook reference cases, replay tests against calibrated recorded
nights, parsers with recorded and malformed responses, `OutlookService` cadence and independent
failures. Runs on macOS and Linux. App: `AlertStringsTests` covers the new alert keys; XCTest UI
tests for the new main-screen states with stubbed responses. Server: the existing tests, plus a
check that the service makes no NOAA requests.

**Target Platform**: iOS 26.0+ (iPhone); the alert service on Linux x86_64 (unchanged apart from
the core update).

**Project Type**: Mobile app + portable Swift package (+ the existing alert service, rules
update only).

**Performance Goals**: Cached snapshot shown with the headline within 1 s (SC-008); computing
the soon signal and both nights' outlook in well under 50 ms on the device. The outlook samples
the sun and moon every 5 minutes over up to about 48 hours, about 600 evaluations.

**Constraints**: Requests identical for every user (FR-018). Refetch at most every 5 min for
solar wind, 60 min for Kp and alerts, and 3 h for the cloud forecast (R8). Foreground only, no
background fetching. Any NOAA failure is local to its section (FR-020). Strings in fi, sv and en.

**Scale/Scope**: 3 NOAA products and 1 FMI query; about 12 new core types; 2 new main-screen
sections and details additions; about 45 strings in three languages; 3 calibration and
recording scripts.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.* Checked against
constitution v1.1.0.

| Principle | Check | Status |
|---|---|---|
| I. Open Data Only | New sources are free and open: NOAA SWPC (NWS public domain) and FMI open data (CC BY 4.0). Licences and terms are recorded in research R12 before use, and attribution is shown (FR-021). Polling stays no faster than the data updates (R8); the FMI forecast is fetched every 3 h against a 6 h cache lifetime. The alert service adds no new source. Calibration-only datasets (OMNI, GFZ Kp, JPL Horizons) are open and documented. "FMI open data is the primary source" still holds: R is the headline. | Pass |
| II. Privacy by Design | Every new request is identical for all users. The cloud forecast asks for all ten zones at once, so it is stronger than the spec's zone-level allowance. The moon is computed on the device. No backend change and nothing new stored (FR-025). NOAA is named in the privacy policy; the App Store label stays "Data Not Collected" (FR-022). | Pass |
| III. Shared Core, Native Shells | Moon, rules, parsers, calculators and `OutlookService` live in `AuroraCore` with Foundation only and are checked by `tools/check-core-portability.sh` and the Linux test run. The app only renders and stores the snapshot. The alert service gets the moon through the shared `ChanceCalculator`. | Pass |
| IV. Test-First | Every rule has reference cases in contracts written before the code (chance v2 1–22, soon 1–12, outlook 1–10). Moon against recorded Horizons values. Parsers against recorded fixtures. No live network in tests. | Pass |
| V. Performance & Efficiency | Separate cache shown immediately; no work added to the headline's path. About 36 KB per hour in the foreground, none in the background. Calculations run off the main actor in the service actor. | Pass |
| VI. Native, Polished UX | Explicit states for each new section ([main-screen-additions.md](contracts/main-screen-additions.md)). The headline stays first and largest, and forecasts are visibly and audibly labelled as forecasts. Dynamic Type, VoiceOver and no colour-only meaning. UI built with `ios-ui-craft`. | Pass |
| Constraints | No new dependency. The backend is unchanged apart from the shared rules, and the app works without it. AGPL unaffected (formulas, not code). | Pass |
| Workflow | Feature branch `003-aurora-outlook`, PR with this check. The R9 strings change goes to `main` before 2.0's App Store submission, on its own short branch and PR. | Pass |

**Post-design re-check (after Phase 1)**: Pass. Design choices that came out of Phase 1:

- The cloud forecast became one shared request, improving on Principle II.
- `OutlookService` stays separate from `AuroraService`, so a NOAA failure cannot reach the
  headline (Principle V and FR-020).
- The moon alert text is a cross-feature dependency on the 2.0 release (R9), recorded under
  Spec amendments and in the Workflow row.

## Spec amendments from research

Applied to [spec.md](spec.md) in this planning step:

- **FR-006**: the rule uses Bz and speed; density is shown but not used (R6).
- **FR-007**: the solar wind staleness limit is 20 minutes, not 15, because the propagated
  product normally runs about 8 minutes behind and is fetched every 5 minutes (R1, R8).
- **FR-008**: the time window comes from SWPC's modelled arrival time, not from the speed (R1).
- **FR-015, FR-018, Privacy Review**: the cloud forecast is one request for all zones;
  every new request is identical for all users (R5).
- **Assumptions**: NOAA licence wording (public domain, no logo) and product instability (R12, R1).

Not a spec change but a release dependency: **R9**, the alert keys for "Moderate – bright moon"
must be in 2.0 before App Store submission.

## Project Structure

### Documentation (this feature)

```text
specs/003-aurora-outlook/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── chance-rules.md              # v2: moon as a sky-brightness step, alert keys, cases 1–22
│   ├── soon-rules.md                # Ey rule, bands, arrival window, cases 1–12
│   ├── outlook-rules.md             # nights, Kp mapping, watches, cases 1–10
│   ├── noaa-data.md                 # NOAA + FMI forecast inputs, parsing, cadence
│   ├── aurora-core-outlook-api.md   # core additions
│   └── main-screen-additions.md     # soon line, outlook rows, details, states
├── checklists/requirements.md
└── tasks.md                         # created by /speckit-tasks
```

### Source Code (repository root)

```text
Packages/AuroraCore/
├── Sources/AuroraCore/
│   ├── Sky/
│   │   ├── SolarPosition.swift        # CHANGED: expose apparent longitude / RA / Dec for the moon
│   │   └── MoonPosition.swift         # NEW: MoonState, MoonPhase (R4)
│   ├── Chance/ChanceCalculator.swift  # CHANGED: v2 rules, moonBright, LimitingFactor.moon, brightMoon reason
│   ├── Model/                         # CHANGED: Levels (new cases), Result (AuroraResult.moon)
│   ├── NOAA/                          # NEW
│   │   ├── NOAARequests.swift
│   │   └── NOAAParser.swift           # propagated solar wind, Kp forecast, watches
│   ├── FMI/FMIRequests.swift          # CHANGED: cloudForecast(zones:)
│   ├── Outlook/                       # NEW
│   │   ├── Band.swift
│   │   ├── SoonCalculator.swift
│   │   ├── Nights.swift               # dark periods, relevant hours
│   │   ├── OutlookCalculator.swift
│   │   ├── OutlookModels.swift        # SolarWindSample, SoonSignal, KpForecast, StormWatch, CloudForecast, NightOutlook, Outlook, OutlookSnapshot
│   │   └── OutlookService.swift       # actor, cadence, OutlookCache, InMemoryOutlookCache
│   ├── AuroraService.swift            # CHANGED: compute the moon, pass to the rules
│   └── Alerts/
│       ├── ZoneEvaluator.swift        # CHANGED: moon at zone position
│       └── AlertMessage.swift         # CHANGED: brightMoon keys (R9)
└── Tests/AuroraCoreTests/
    ├── ChanceCalculatorTests.swift    # CHANGED: v2 cases
    ├── MoonPositionTests.swift        # NEW
    ├── Outlook/                       # NEW: Soon, SoonReplay, KpMapping, OutlookCalculator, Nights, OutlookService
    ├── NOAAParserTests.swift          # NEW
    └── Fixtures/outlook/              # NEW (R10), moon references (R4), calibration nights (R6, R7)

Revontulet/
├── MainScreen/
│   ├── MainScreenModel.swift          # CHANGED: runs OutlookService next to AuroraService
│   ├── MainScreenView.swift           # CHANGED: soon line, outlook section
│   ├── OutlookSectionView.swift       # NEW
│   ├── ChanceDetailsView.swift        # CHANGED: moon, solar wind, outlook details, NOAA attribution
│   └── CoreLabels.swift               # CHANGED: labels for new enums
├── Platform/FileOutlookCache.swift    # NEW
├── App/UITestHTTPClient.swift         # CHANGED: NOAA and forecast stubs, -uitest-outlook scenarios
└── Resources/Localizable.xcstrings    # CHANGED: ~45 strings × fi/sv/en

RevontuletUITests/OutlookUITests.swift # NEW

Server/                                # no source change; rebuilt with the updated core

tools/
├── record-outlook-fixtures.py         # NEW (R10)
├── record-moon-reference.py           # NEW (R4)
├── calibrate-soon.py                  # NEW (R6)
└── calibrate-kp.py                    # NEW (R7)
```

**Structure Decision**: Same three-part layout as features 001 and 002. All new domain logic is
in `AuroraCore` under new `NOAA/` and `Outlook/` folders, with the moon beside the sun in
`Sky/`. The app adds one view and one cache. The alert service needs no source change because it
already calls `ZoneEvaluator`.

## Delivery order

1. **R9 strings into 2.0**: a separate branch and PR on `main` before App Store submission.
2. **P1 Moon**: moon position, chance-rules v2, `AuroraResult.moon`, `ZoneEvaluator`,
   `AlertMessage`, details. Shippable on its own.
3. **Calibration**: R6 and R7 scripts. Fix the thresholds in the contracts before P2 and P3
   tests are final.
4. **P2 Soon**: parser, calculator, service, soon line.
5. **P3 Outlook**: Kp and watch parsers, cloud forecast, nights, calculator, outlook section.
6. Privacy policy text (FR-022) and the NOAA attribution before release.

## Complexity Tracking

No constitution violations.
