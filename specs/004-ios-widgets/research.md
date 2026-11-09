# Research: iOS Widgets

Decisions that resolve the open technical questions in [plan.md](plan.md). No NEEDS CLARIFICATION
markers were left in the spec; these are implementation choices.

## R1. How widgets get data

**Decision**: Each timeline reload reads the shared cache first. If the cached result is for the
same place and younger than the magnetometer interval (5 min), it is used as is. Otherwise the
provider calls the existing `AuroraService.refresh` (and, for the medium widget only,
`OutlookService.refresh`), which store into the same cache the app reads.

**Rationale**: FR-019 to FR-022 and constitution I (never poll more often than the data updates).
`AuroraService` keeps its due times in memory, and the extension is a different process from the
app, so the freshness check cannot rely on that memory; the cached result's `computedAt` is the
one value both processes see. Reusing the services means the widget cannot disagree with the app
about the level (SC-002).

**Alternatives considered**: (a) The app fetches in the background and the widget only reads. Rejected
by the user: widgets refresh themselves, no app background task. (b) A separate widget-only
fetch path. Rejected: duplicates rules, risks disagreement. (c) A server push to the widget.
Rejected: needs a backend beyond alerts (constitution II).

## R2. Refresh rhythm

**Decision**: `WidgetRefreshPolicy` suggests the next reload date from the place and the time:
15 minutes while it is not "too light" at the place and the aurora season is on (the same darkness
function the alert season uses); otherwise the next time it gets dark minus 15 minutes, capped at
3 hours. Each timeline also carries a second entry at the moment the data turns stale
(`measuredAt` plus 30 minutes, the app's outdated limit), so the stale look shows without a reload.

**Rationale**: The system gives a widget a limited daily reload budget and treats the date as a
hint; asking for 15 minutes only when it matters spends the budget where activity matters, and the
stale entry keeps the display honest when the system holds reloads back (Low Power Mode, FR-022).
The data itself updates every 10 s to 5 min, so more frequent reloads would be useless.

**Alternatives considered**: Fixed 30 or 60 minutes: wasteful in daylight, too slow on active nights.
`.never` plus app-driven reloads only: breaks US4 (app closed for days).

## R3. Drawing the app's aurora in a widget

**Decision**: Extract the curtain drawing from `SkyBackground` into a shared `AuroraCurtains`
view with parameters for baseline/height set (screen or widget framing), intensity, magenta and
phase. The app passes the moving phase; the widget passes phase 0, fixed 5 px blur, `screen`
blend, and adds the dark bottom fade. If `Canvas` plus blur does not render reliably in the widget
renderer, the fallback is to render the still frame with `ImageRenderer` in the provider and store
it in the entry as an `Image`.

**Rationale**: FR-024 and the approved draft; one drawing means the widget and app cannot drift
apart. Blur is fixed at 5 px because the user checked 5, 3, 1.5 and 0 px in the draft and 5 px kept
the text clearest.

**Alternatives considered**: A pre-rendered PNG per level: four assets, would not match future
tweaks to the curtains, and cannot dim smoothly for stale. A gradient imitation: the user rejected
imitations; the app's own curtains were chosen.

## R4. Level without colour, and the tinted modes

**Decision**: The level word (Home Screen) or gauge position (Lock Screen) carries the level; the
glyph and artwork only reinforce it. In `.accented`/`.vibrantAccented` rendering the artwork group
is marked `widgetAccentable(false)` content that the system desaturates; text and gauge use
`widgetAccentable()` so the system tints them. The circular and rectangular gauge use the four-step
fill, not a continuous value.

**Rationale**: FR-006, FR-016, FR-024. The Lock Screen is monochrome by system rule.

## R5. Place and municipality name in the extension

**Decision**: The place comes from the shared selection. For a chosen municipality, a new
`MunicipalityNames` lookup in the core decodes only code, names and the representative point from
the bundled JSON (the decoder skips the polygons). For `currentLocation`, the widget uses the
`place` stored in the last cached result and never asks for a fix; if there is no cached result,
there is no place and the "open the app" state shows.

**Rationale**: FR-011, FR-021 and the spec assumption "widgets use the stored place". `PlaceResolver`
decodes all boundaries (1.5 MB of polygons) and builds a search index, which the widget does not
need and which is wasteful under the extension memory limit.

**Alternatives considered**: Load `PlaceResolver` in the widget: simplest but heavy. Store the
resolved name in the group defaults: adds a second source of truth that can disagree with the
result's place.

## R6. Sharing storage between app and extension

**Decision**: App Group `group.fi.juusimaa.revontulet`. `last-result.json` and `last-outlook.json`
move to the group container; the place selection moves to `UserDefaults(suiteName:)`. The app
copies old files and the old defaults value once at launch, before creating the caches, and leaves
the old files in place until the next version removes them. The extension never migrates.

**Rationale**: App and extension are separate sandboxes; an App Group is the supported way to share
on-device data, and it keeps FR-014 (nothing leaves the device). Atomic writes (already used)
make a concurrent read from the other process safe.

**Alternatives considered**: Keychain sharing or iCloud: unnecessary and, for iCloud, off-device.
Only the app writes, widget read-only: contradicts FR-019.

## R7. Concurrency inside and across processes

**Decision**: Inside the extension a single actor, `WidgetDataLoader`, owns the service instances
and coalesces concurrent loads, so several widgets reloading together make one fetch. Across the
app and extension processes the cache check (R1) is the guard; a rare duplicate fetch is accepted
because both write the same atomic file and both stay within the FMI limits.

**Rationale**: constitution I and FR-020 without a cross-process lock, which iOS does not give
extensions cheaply. A failed or cut-short fetch writes nothing, so the previous result stays whole.

## R8. Project and signing setup

**Decision**: Add an `app-extension` target `RevontuletWidgets` in `project.yml` (bundle id
`fi.juusimaa.revontulet.widgets`), embedded in the app, with its own entitlements (App Group
only). The `Shared/` sources and `Localizable.xcstrings` are listed in both targets. The new
capability is switched on by hand for both App IDs in the developer portal first.

**Rationale**: Matches the project's XcodeGen workflow and the known Xcode Cloud failure (exit 70)
when a capability is missing on the App ID.

## R9. Privacy manifest and App Store label

**Decision**: The extension gets its own `PrivacyInfo.xcprivacy` declaring the same required-reason
API use as the app (UserDefaults, `CA92.1`, extended with the App Group reason if App Store
Connect asks) and file-timestamp access only if the build reports it. No collected data types.

**Rationale**: App Store processing requires a manifest per bundle that uses these APIs; the label
stays "Data Not Collected" because nothing new is collected or sent (FR-018, SC-007).

## R10. Opening the app on tap

**Decision**: No custom URL scheme. A tap on any widget opens the app, which already lands on its
main screen (FR-010). Lock Screen widgets ask for unlock first by system behaviour.

**Rationale**: Nothing to register, nothing to parse, nothing to attack. A deep link can be added
later if a second destination appears.

## R11. Telling widgets about new data

**Decision**: After the app stores a result and after the place selection changes, it calls
`WidgetCenter.shared.reloadAllTimelines()`. The call is skipped when the stored result is
identical in level, reason, place and measured time to the previous one.

**Rationale**: SC-003 (new data on the Home Screen within 5 seconds) and FR-012. App-initiated
reloads while the app is in use do not need a budget from the extension; skipping identical results
avoids pointless redraws.

## R12. Strings

**Decision**: Widget text uses the same `Localizable.xcstrings` as the app (compiled into both
targets), with the widget's new keys added once for en, fi and sv. `CoreLabels.swift` moves to
`Shared/` so the level, reason and outlook words come from the same code.

**Rationale**: FR-002 and FR-015: the same words, three languages, one catalog that cannot drift.
The unused app keys add a few KB to the extension; acceptable.

**Alternatives considered**: A second catalog in the extension: two places to keep in sync.
