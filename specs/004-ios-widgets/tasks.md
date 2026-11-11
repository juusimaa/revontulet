# Tasks: iOS Widgets

**Input**: Design documents from `specs/004-ios-widgets/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Core logic is test-first (constitution IV): each core test task comes before, and must be seen failing before, its implementation. Widget UI has no XCUITest (XCUITest cannot drive widgets); it is covered by previews, simulator screenshots (`ios-ui-craft` loop, constitution VI) and the device checks in quickstart.md. App-side logic (migration, stores, provider) has XCTest.

**Organization**: Grouped by user story. US1 is the MVP: the small and medium Home Screen widgets showing the cached result. US4 adds the self-refresh.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 Home Screen glance, US2 Lock Screen, US3 honest states, US4 self-refresh
- Paths are from the repository root; run `xcodegen generate` after any `project.yml` change.

---

## Phase 1: Setup

**Purpose**: The extension target, the shared source group and the signing prerequisites.

- [x] T001 Enable the App Group `group.fi.juusimaa.revontulet` by hand in the developer portal on App ID `fi.juusimaa.revontulet` and create App ID `fi.juusimaa.revontulet.widgets` with the same App Group (otherwise the Xcode Cloud export fails with exit 70); note done in specs/004-ios-widgets/quickstart.md prerequisites
- [x] T002 Create the `Shared/` group and move `Revontulet/Platform/FileResultCache.swift`, `Revontulet/Platform/FileOutlookCache.swift` and `Revontulet/MainScreen/CoreLabels.swift` into it with `git mv`, changing no behaviour yet
- [x] T003 Add the `RevontuletWidgets` app-extension target to `project.yml` (bundle id `fi.juusimaa.revontulet.widgets`, iOS 26, Swift 6 strict concurrency, depends on AuroraCore, sources `RevontuletWidgets/`, `Shared/` and `Revontulet/Resources/Localizable.xcstrings`), embed it in the `Revontulet` target, add `Shared/` to the app sources, and add `RevontuletWidgets` to the scheme build
- [x] T004 [P] Add the App Group entitlement to `Revontulet/Revontulet.entitlements` (keep `aps-environment`) and create `RevontuletWidgets/RevontuletWidgets.entitlements` with the App Group only, and point `CODE_SIGN_ENTITLEMENTS` at it in `project.yml`
- [x] T005 [P] Create `RevontuletWidgets/Resources/PrivacyInfo.xcprivacy` (no tracking, no collected data types, UserDefaults reason `CA92.1`; add file-timestamp or App Group reasons only if the build reports them)
- [x] T006 Add a minimal `@main` `WidgetBundle` in `RevontuletWidgets/RevontuletWidgetsBundle.swift` with one placeholder widget in `RevontuletWidgets/AuroraWidget.swift`; run `xcodegen generate` and confirm both targets build

---

## Phase 2: Foundational (blocks all user stories)

**Purpose**: Core types, the shared store and the shared sky, which every widget needs.

**CRITICAL**: No story work starts before this phase is done.

### Core (test-first)

- [x] T007 [P] Write failing tests in `Packages/AuroraCore/Tests/AuroraCoreTests/Widgets/WidgetSnapshotTests.swift`: each level and reason copied from the result; `isStale` true at 30 min + 1 s and false at exactly 30 min ("older than 30 min", the app's `AuroraResult.outdatedAfter`); outlook of another municipality ignored (`soon` and `tonight` nil); outlook missing; R value missing
- [x] T008 [P] Write failing tests in `Packages/AuroraCore/Tests/AuroraCoreTests/Widgets/WidgetRefreshPolicyTests.swift`: `resultNeedsFetch` at 4:59, 5:00 and 5:01 minutes, other municipality, no cache, `computedAt` in the future; `outlookNeedsFetch` with the same cases; `nextReload` is always strictly after `now` (Oulu in December is `now + 15 min`; polar summer is capped at `now + 3 h`; dusk approaching is 15 min before dark but not earlier than `now + 15 min`); `staleMoment` is `measuredAt + 30 min`
- [x] T009 [P] Write failing tests in `Packages/AuroraCore/Tests/AuroraCoreTests/Widgets/MunicipalityNamesTests.swift`: a known code gives the same names and representative point as `PlaceResolver.municipality(code:)`; an unknown code gives nil
- [x] T010 [P] Implement `WidgetSnapshot` per contracts/widget-core-api.md in `Packages/AuroraCore/Sources/AuroraCore/Widgets/WidgetSnapshot.swift` until T007 passes (no recomputation: level and reason come from the stored result via `result.reason`)
- [x] T011 [P] Implement `WidgetRefreshPolicy` in `Packages/AuroraCore/Sources/AuroraCore/Widgets/WidgetRefreshPolicy.swift` until T008 passes (reuse `SolarPosition.darkness`, 15-minute scan over 24 h as `AlertSeason` does; magnetometer interval 5 min)
- [x] T012 [P] Implement `MunicipalityNames.lookup(code:)` in `Packages/AuroraCore/Sources/AuroraCore/Places/MunicipalityNames.swift` decoding only code, names and point (never polygons) until T009 passes
- [x] T013 Run `swift test` in `Packages/AuroraCore` on macOS and confirm the Linux CI workflow `.github/workflows/alert-service.yml` still covers the package (no new Apple-only imports)

### Shared store (app side, test-first)

- [x] T014 [P] Write failing tests in `RevontuletTests/SharedStorageTests.swift`: migration copies `last-result.json` and `last-outlook.json` from Application Support once, never overwrites an existing group file, tolerates a missing source; copies `placeSelection` from `UserDefaults.standard` to the suite only when the suite has none; a second store instance on the same suite and directory sees the first one's writes (use temporary directories and a unique suite name)
- [x] T015 [P] Create `Shared/AppGroup.swift` with the group identifier, the container URL (injectable for tests) and the shared `UserDefaults` suite
- [x] T016 Change `Shared/FileResultCache.swift` and `Shared/FileOutlookCache.swift` so `defaultURL` is in the App Group container (`last-result.json`, `last-outlook.json`), keeping atomic write and backup exclusion
- [x] T017 Move `Revontulet/Platform/PlaceSelectionStore.swift` to `Shared/PlaceSelectionStore.swift`, read and write `placeSelection` in the group suite, and make reading usable from the extension (no `@MainActor` requirement for reads); the extension never writes it
- [x] T018 Create `Shared/StorageMigration.swift` per contracts/shared-storage.md (copy once, leave old files in place) and call it from `Revontulet/App/RevontuletApp.swift` before the caches and the place store are created; make T014 pass
- [x] T019 Run the full app test suite and confirm the existing UI tests that use `-uiTestResetCache` still reset the new locations (`RevontuletUITests`, `Revontulet/App/RevontuletApp.swift`)

### Shared sky and strings

- [x] T020 Extract the curtain drawing from `Revontulet/MainScreen/SkyBackground.swift` into `Shared/Sky/AuroraCurtains.swift` (intensity, magenta, phase, and a framing parameter: screen baselines 0.36/0.27 and widget baselines from specs/004-ios-widgets/ui-draft/widgets.html); `SkyBackground` uses it and looks identical in the app (check with a simulator screenshot before and after)
- [x] T021 Add the widget strings to `Revontulet/Resources/Localizable.xcstrings` for en, fi and sv: "Old data", "Open Revontulet to choose a place", the sample marker, the VoiceOver sentence formats, age formats and the Lock Screen "Aurora" word; reuse existing level, reason and no-data keys

**Checkpoint**: core and shared tests pass; the app is unchanged to the eye; the extension builds.

---

## Phase 3: User Story 1 - Home Screen glance (P1) 🎯 MVP

**Goal**: Small and medium widgets show the cached level, reason, place and age, and the medium one the R value, station, soon and tonight.

**Independent Test**: With the app having produced a result, add the small widget and check level, reason, place and age match the main screen; add the medium widget and check the extra detail matches the app's details and outlook; tap opens the app (quickstart section 3).

- [x] T022 [US1] Spike (do first): render `AuroraCurtains` with 5 px blur and `screen` blend inside a `containerBackground(for: .widget)` in `RevontuletWidgets/Views/WidgetSky.swift`, check on the simulator that `Canvas` plus blur renders and stays within memory; if not, switch to an `ImageRenderer` still image carried in the entry (research R3) and record the outcome in specs/004-ios-widgets/research.md R3
- [x] T023 [P] [US1] Create the vector aurora glyph (curtain with rays, option A) in `RevontuletWidgets/Views/AuroraGlyph.swift`, tintable by level, matching specs/004-ios-widgets/ui-draft/widgets.html
- [x] T024 [P] [US1] Create the shell entry and a cache-only `AuroraProvider` in `RevontuletWidgets/AuroraProvider.swift`: read the shared selection and result cache, build the place per contracts/widget-refresh.md (municipality via `MunicipalityNames`, current location via the cached result's place), build `WidgetSnapshot.make` and one entry; the "same municipality" rule applies to the outlook
- [x] T025 [US1] Build `RevontuletWidgets/Views/SmallView.swift`: glyph in the top line tinted by level, level word first and largest, reason second, place and data age last; sky from `WidgetSky` with the bottom fade; `ios-ui-craft` screenshot loop in light, dark, tinted and clear icon styles; level never by colour alone
- [x] T026 [US1] Build `RevontuletWidgets/Views/MediumView.swift`: the small widget's headline on the left, R value with station, Soon and Tonight on the right, "clouds not included" note when `cloudsIncluded` is false; omit the outlook rows when `soon` and `tonight` are nil
- [x] T027 [US1] Register `systemSmall` and `systemMedium` in `RevontuletWidgets/AuroraWidget.swift` with the gallery name and description, no `widgetURL` (a tap opens the app, FR-010)
- [x] T028 [US1] Add the one-sentence VoiceOver label and hide the artwork and glyph from VoiceOver in both views (contracts/widget-refresh.md, Accessibility); check Dynamic Type up to the largest accessibility size and fi, sv, en (level word never truncated, place truncates first)
- [x] T029 [US1] In `Revontulet/MainScreen/MainScreenModel.swift` call `WidgetCenter.shared.reloadAllTimelines()` after a result is stored and after the selection changes, skipping it when the new result equals the previous one in level, reason, municipality and `measuredAt` (research R11)
- [x] T030 [US1] Run quickstart section 3 on the simulator for the four levels and fix any layout or legibility finding; save screenshots to specs/004-ios-widgets/ui-draft/screenshots/

**Checkpoint**: small and medium widgets work from the cache and agree with the main screen.

---

## Phase 4: User Story 2 - Lock Screen (P2)

**Goal**: Circular, rectangular and inline widgets answer the question without unlocking.

**Independent Test**: Add each variant; read them on light, dark and tinted Lock Screens and in the always-on look; tap asks to unlock and opens the app (quickstart section 3, steps 4-6).

- [ ] T031 [P] [US2] Build `RevontuletWidgets/Views/CircularView.swift`: the glyph centred inside a four-step gauge filled to the level, no word in the ring, `AccessoryWidgetBackground`
- [ ] T032 [P] [US2] Build `RevontuletWidgets/Views/RectangularView.swift`: gauge or glyph, level, reason and data age in at most three short lines, system vibrancy, accentable text
- [ ] T033 [P] [US2] Build `RevontuletWidgets/Views/InlineView.swift`: one line "Aurora: <Level>" (and the place if it fits); in the stale state the wording itself says "Old data" because the inline widget shows no age (FR-007)
- [ ] T034 [US2] Register `accessoryCircular`, `accessoryRectangular` and `accessoryInline` in `RevontuletWidgets/AuroraWidget.swift`, add the VoiceOver sentences, and check reduced-luminance and tinted looks plus the largest text sizes in fi, sv, en
- [ ] T035 [US2] Run the Lock Screen part of quickstart section 3 on the simulator and the phone; save screenshots to specs/004-ios-widgets/ui-draft/screenshots/

**Checkpoint**: all five layouts render for current data.

---

## Phase 5: User Story 3 - Honest states (P2)

**Goal**: Stale, offline with cache, no place, no data, placeholder and gallery sample each look distinct and honest.

**Independent Test**: Fresh install shows "Open Revontulet to choose a place"; ageing past 30 min shows the dimmed "Old data"; airplane mode keeps the last result marked; gallery shows a clearly labelled sample (quickstart section 4).

- [ ] T036 [P] [US3] Write failing provider tests in `RevontuletTests/WidgetProviderTests.swift` (stub `HTTPClient`, injected clock, temporary stores): no selection and no cache gives `noPlace` and no network request; a result older than "older than 30 min" gives `stale`; a no-data result gives `noData`; a result for an out-of-coverage place gives `noPlace`
- [ ] T037 [US3] Add the `WidgetState` enum (`current`, `stale`, `noPlace`, `noData`, `placeholder`/`sample`) to `RevontuletWidgets/AuroraProvider.swift` and make the provider choose it per data-model.md; make T036 pass
- [ ] T038 [P] [US3] Add the stale look to `WidgetSky` and the views: artwork dimmed to 20% of its level strength, text at full contrast, "Old data" and age, in all five layouts
- [ ] T039 [P] [US3] Design the `noPlace` and `noData` layouts in all five families (the app's no-data and out-of-coverage wording, no level, glyph kept so the widget stays recognisable); `ios-ui-craft` screenshot loop
- [ ] T040 [US3] Implement `getSnapshot` and `placeholder`: in the gallery (`context.isPreview`) show a plausible sample marked as a sample; placeholder uses a redacted layout
- [ ] T041 [US3] Add a second timeline entry at `WidgetRefreshPolicy.staleMoment(measuredAt:)` when it is in the future so the stale look appears without a reload; extend T036 to check the entries
- [ ] T042 [US3] Run quickstart section 4 (all states, all families, three languages, largest text size) and fix findings

**Checkpoint**: no state leaves a blank or misleading tile.

---

## Phase 6: User Story 4 - Self-refreshing widgets (P2)

**Goal**: Widgets fetch for themselves, sparingly, with the app closed.

**Independent Test**: With five widgets reloading together there is one magnetometer request; fresh cache means none; app closed for an evening and the data time advances (quickstart section 5).

- [ ] T043 [P] [US4] Extend `RevontuletTests/WidgetProviderTests.swift` with failing tests: stale cache triggers exactly one `AuroraService.refresh` for several concurrent loads; fresh cache triggers none; a failed or offline fetch leaves the stored result unchanged and still returns an entry from it; `force` is never set; the outlook is fetched only for `systemMedium`
- [ ] T044 [US4] Create the `WidgetDataLoader` actor in `RevontuletWidgets/WidgetDataLoader.swift` that owns the `AuroraService` and `OutlookService` (shared stores from `Shared/`), coalesces concurrent loads and applies `WidgetRefreshPolicy.resultNeedsFetch` / `outlookNeedsFetch` (research R1, R7)
- [ ] T045 [US4] Wire `WidgetDataLoader` into `AuroraProvider`: fetch when due, never when no place is chosen (FR-021), return the cached entry if the time allowance runs short and cancel the fetch so nothing is written (contracts/widget-refresh.md); make T043 pass
- [ ] T046 [US4] Set the timeline policy to `.after(WidgetRefreshPolicy.nextReload(after:at:))`, and `.after(now + 60 min)` when there is no place
- [ ] T047 [US4] Verify on the simulator and the phone (quickstart section 5): one request for several widgets, none when fresh, new place within 5 seconds of returning to the Home Screen, data time advancing over an evening with the app closed, stale look under Low Power Mode

**Checkpoint**: widgets stay current without the app.

---

## Phase 7: Polish and cross-cutting

- [ ] T048 [P] Verify the privacy gates in quickstart section 6: the extension links no CoreLocation, makes only the app's FMI and NOAA requests, an archive build's privacy report shows no new collected data; update `docs/privacy.md` to mention the widgets read the stored place on the device only
- [ ] T049 [P] Update the App Store texts and screenshots plan for widgets in `docs/` (what the widgets show, nothing collected)
- [ ] T050 Review all five layouts once more against the checks in spec.md SC-001 to SC-008 (largest text, fi, sv, en, tinted, always-on) and record the result in specs/004-ios-widgets/checklists/requirements.md notes
- [ ] T051 Bump `MARKETING_VERSION` in `project.yml` to `5.0` on the branch before the first TestFlight checkpoint (release flow), run a full `xcodebuild test` and confirm the Xcode Cloud export succeeds with the new App ID and App Group
- [ ] T052 Run the whole quickstart.md end to end on the phone with `DEVELOPMENT_TEAM=ET83UX2UD2` and tick the scenarios off

---

## Dependencies and execution order

- **Phase 1** first. T001 (portal) must be done before any device or Xcode Cloud build; simulator work can start without it.
- **Phase 2** blocks all stories. Inside it: T007-T009 before T010-T012; T014 before T015-T018; T020 and T021 are independent of the core and storage tasks.
- **US1** depends on Phase 2. T022 (spike) comes first and may change `WidgetSky` and the entry type.
- **US2** depends on Phase 2 and on T023 (glyph) and T024 (provider); otherwise independent of US1's views.
- **US3** depends on US1's provider and views (it adds states to them).
- **US4** depends on US1's provider; it can run in parallel with US2 and US3 on separate files, but T043-T045 edit `AuroraProvider.swift` together with US3's T037, so do those two in sequence.
- **Polish** last.

## Parallel opportunities

- Phase 1: T004, T005 together.
- Phase 2: T007, T008, T009 together, then T010, T011, T012 together; T014, T015 together; T020 alongside the storage tasks.
- US1: T023 and T024 together, then T025 and T026 together.
- US2: T031, T032, T033 together.
- US3: T036, T038, T039 together.

## Implementation strategy

**MVP**: Phases 1, 2 and US1 (small and medium widgets from the cache) give a complete, shippable widget that refreshes whenever the app stores a result. Validate with quickstart section 3, then continue.

**Incremental**: US2 adds the Lock Screen, US3 the honest states (needed before release, constitution VI), US4 the self-refresh (needed to meet the spec's purpose and SC-008). Release 5.0 with US1-US4 together; the earlier stories are TestFlight checkpoints only.

## Notes

- Commit after each task or small group; every commit must build and pass the tests (constitution).
- Do not add new data sources, new rules or app background refresh; the plan excludes them.
- The signatures in contracts/widget-core-api.md were written from reading the code and have not been compiled; adjust the contract file if a signature must change.
