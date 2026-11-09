# Implementation Plan: iOS Widgets

**Branch**: `004-ios-widgets` | **Date**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-ios-widgets/spec.md`

## Summary

Five widgets (small and medium Home Screen; circular, rectangular and inline Lock Screen) in one
new WidgetKit extension, `RevontuletWidgets`. They add no data and no rules: each draws a
`WidgetSnapshot` built from the app's existing `AuroraResult` (and `OutlookSnapshot` for the
medium one).

Three design moves carry the feature (details in [research.md](research.md)):

1. **One shared on-device store.** The result cache, the outlook cache and the place selection move
   into an App Group container that the app and the widget extension both read and write. The app
   migrates the old files on first launch. Nothing leaves the device.
2. **The widgets fetch for themselves.** A timeline reload asks a small policy in `AuroraCore`
   whether the cached result is still fresh (same place, under 5 minutes old). Only if not does it
   call the existing `AuroraService` / `OutlookService`, which write to the shared cache. Several
   widgets reloading together therefore share one fetch, and a failed fetch leaves the stored
   result untouched. The policy also suggests the next reload time (tight on dark nights in season,
   sparse otherwise) and the moment the entry turns stale, so the stale look appears on time even
   without a reload.
3. **The app's own sky, as a still frame.** The curtain drawing in `SkyBackground` is extracted
   into one shared view used by the app (animated) and the widgets (phase 0, 5 px blur, dark bottom
   fade). The widgets look like the app because they run the same drawing code.

The app tells WidgetKit to reload when it stores a new result or the place changes (SC-003). There
is no app-level background refresh for widgets (spec Assumptions).

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.1), Swift 6 language mode, strict concurrency complete
(as `project.yml`).

**Primary Dependencies**: None new. WidgetKit and SwiftUI in the extension; Foundation only in the
core additions. Swift Package Manager only (constitution).

**Storage**: App Group container `group.fi.juusimaa.revontulet`: `last-result.json`,
`last-outlook.json` (moved from Application Support) and the place selection in the group's
`UserDefaults` suite (moved from `.standard`). One-time migration in the app; the widget never
migrates. No server storage.

**Testing**: Swift Testing in `AuroraCore` (macOS and Linux), written first: `WidgetSnapshot`
builder, `WidgetRefreshPolicy` (fresh/due, next reload, stale moment, season and darkness),
municipality name lookup. App-side XCTest for the migration, the shared stores and the provider
(stub `HTTPClient`, injected clock): no place, stale, offline-with-cache, shared fetch. UI of the
widgets: screenshot-driven iteration per `ios-ui-craft` on the simulator (Xcode previews and the
widget gallery) plus the device checks in [quickstart.md](quickstart.md); XCUITest cannot drive
widgets, so that is the noted reason for no UI tests (constitution IV).

**Target Platform**: iOS 26.0+ (iPhone). Widget families: `systemSmall`, `systemMedium`,
`accessoryCircular`, `accessoryRectangular`, `accessoryInline`.

**Project Type**: Mobile app + portable Swift package (+ alert service, untouched).

**Performance Goals**: The widget renders from the cache at once; a refresh that has to fetch
finishes well inside the system's limit (one magnetometer request, optionally a cloud request, and
for medium the outlook requests). Widget memory stays far below the extension limit: the municipality
boundaries (1.5 MB of polygons) are never decoded in the widget (R5).

**Constraints**: Same requests, same limits as the app (FR-014, constitution I): magnetometer at
most every 5 min, clouds every 10 min, outlook inputs at their own intervals; never from a widget
with fresh data in the shared cache. No location access, no analytics, no accounts. Widget reload
budget is the system's; the plan only suggests dates. Largest accessibility sizes and fi/sv/en
must not clip the level word.

**Scale/Scope**: 5 widget layouts, 1 extension target, 1 shared sky view, about 6 new core types,
about 25 new strings in three languages.

## Constitution Check

*GATE: passed before Phase 0; re-checked after Phase 1 design (below).*

| Principle | Check | Result |
|---|---|---|
| I. Open Data Only | Widgets fetch the same FMI/NOAA data through the same core services, with the same intervals, and check the shared cache first (FR-020). No new source, so no new licence. Attribution stays in the app. | Pass |
| II. Privacy by Design | No location request in the extension; it uses the stored place (a municipality, or the last result's place) and sends nothing beyond what the app sends. No analytics. The App Group is on-device storage only. The privacy label stays "Data Not Collected" (FR-018). The widget bundle needs its own privacy manifest (R9). | Pass |
| III. Shared Core, Native Shells | Rules, freshness policy, reload suggestion and snapshot building are in `AuroraCore` (no UI imports, Linux-buildable). WidgetKit views, App Group file/defaults stores and the provider are thin native code. | Pass |
| IV. Test-First | Core additions are test-first with recorded-style fixtures and an injected clock; no live network. Widget UI has no XCUITest (not possible); reason recorded in Technical Context; it is covered by previews, simulator screenshots and device checks. | Pass |
| V. Performance & Efficiency | Cache first, then fetch only when due; background work only through WidgetKit timelines (system-scheduled); parsing and calculation off the main actor in the provider; no app background refresh added. | Pass |
| VI. Native, Polished UX | Dynamic Type, VoiceOver sentence, Dark/tinted/Lock Screen modes, explicit stale/offline/no-place/no-data states, data age on every widget but inline; system container background and vibrancy on the Lock Screen. UI work uses `ios-ui-craft` (screenshot loop). | Pass |
| Technology | Swift 6, SwiftUI, iOS 26, SwiftPM only; AGPL unchanged. New App Group capability must be enabled by hand on both App IDs (R8). | Pass |

**Post-design re-check**: unchanged. The data model ([data-model.md](data-model.md)) adds only
derived, device-local values; the contracts add no network surface. No violations, so no
Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/004-ios-widgets/
├── plan.md              # This file
├── research.md          # Phase 0: decisions and rationale
├── data-model.md        # Phase 1: snapshot, store, states
├── quickstart.md        # Phase 1: validation scenarios
├── contracts/
│   ├── widget-core-api.md        # AuroraCore additions
│   ├── shared-storage.md         # App Group files, defaults, migration
│   └── widget-refresh.md         # Provider, reload, app-to-widget signalling
├── ui-draft/widgets.html         # Approved UI direction
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks, not created here)
```

### Source Code (repository root)

```text
Packages/AuroraCore/
├── Sources/AuroraCore/
│   ├── Widgets/
│   │   ├── WidgetSnapshot.swift          # new: what a widget draws, built from result + outlook
│   │   └── WidgetRefreshPolicy.swift     # new: fresh/due, next reload, stale moment
│   └── Places/MunicipalityNames.swift    # new: names/point by code, without polygons (R5)
└── Tests/AuroraCoreTests/Widgets/        # new: written first

Shared/                                   # new group, compiled into the app AND the extension
├── AppGroup.swift                        # group id, container URL, shared UserDefaults
├── FileResultCache.swift                 # moved from Revontulet/Platform, now in the container
├── FileOutlookCache.swift                # moved, same
├── PlaceSelectionStore.swift             # moved; no longer @MainActor-only, reads from the suite
├── StorageMigration.swift                # new: copies old files/defaults once (app only calls it)
├── CoreLabels.swift                      # moved from Revontulet/MainScreen
└── Sky/AuroraCurtains.swift              # new: the curtain drawing extracted from SkyBackground

Revontulet/
├── MainScreen/SkyBackground.swift        # uses AuroraCurtains (animated)
├── MainScreen/MainScreenModel.swift      # reloads widget timelines after a stored result / place change
├── App/RevontuletApp.swift               # runs the migration before the caches are created
├── Resources/Localizable.xcstrings       # gains widget keys; also compiled into the extension
└── Revontulet.entitlements               # + App Group

RevontuletWidgets/                        # new extension target
├── RevontuletWidgetsBundle.swift         # @main WidgetBundle
├── AuroraWidget.swift                    # one Widget, five supported families
├── AuroraProvider.swift                  # TimelineProvider: cache check, fetch, entries
├── Views/                                # SmallView, MediumView, CircularView, RectangularView, InlineView
├── Views/AuroraGlyph.swift               # the curtain-with-rays glyph (vector)
├── Views/WidgetSky.swift                 # curtains + bottom fade + stale dimming
├── Resources/PrivacyInfo.xcprivacy
└── RevontuletWidgets.entitlements         # App Group

RevontuletTests/                          # + migration, stores, provider tests
project.yml                               # + extension target, embed, App Group, shared sources
```

**Structure Decision**: one extension target with one `Widget` that supports all five families
(one gallery entry, one provider, one place to keep the refresh logic) instead of a widget per
size. Code the app and the extension both need lives in a plain `Shared/` source group compiled
into both targets rather than in a new framework: it is a handful of small files, and a framework
target would add a build product to sign and embed for no isolation gain. Domain logic stays in
`AuroraCore` (Principle III).

## Complexity Tracking

No constitution violations to justify.

## Risks and spikes (resolved first in the task order)

- **Canvas in widgets**: the curtain `Canvas` plus blur may not render, or may cost too much, in
  the widget renderer. Spike first on the simulator; the fallback is rendering the still frame to
  an image in the provider with `ImageRenderer` (R3).
- **Tinted / accented rendering mode**: verify the artwork and the glyph with
  `widgetRenderingMode` `.accented` and `.vibrantAccented`; the level word and gauge must carry the
  level (FR-006, FR-024).
- **App ID capabilities**: App Groups must be enabled on `fi.juusimaa.revontulet` and the new
  `fi.juusimaa.revontulet.widgets` App IDs by hand before the first Xcode Cloud build, or the export
  fails with exit 70 (known from earlier releases).
- **Release flow**: bump `MARKETING_VERSION` to 5.0 on the branch before the first TestFlight
  checkpoint, as in the release-flow notes.
