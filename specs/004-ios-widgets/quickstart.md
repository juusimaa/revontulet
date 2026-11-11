# Quickstart: validating the widgets

Run in order. Core scenarios need no device; the widget scenarios use the simulator, the last ones
the phone (the app runs on the iPhone with `DEVELOPMENT_TEAM=ET83UX2UD2`, as in the device-tests
notes). Details of the contracts are in [contracts/](contracts/).

## 0. Prerequisites

- App Group `group.fi.juusimaa.revontulet` enabled on both App IDs
  ([contracts/shared-storage.md](contracts/shared-storage.md)). Done 2026-11-10: group registered,
  added to `fi.juusimaa.revontulet`, App ID `fi.juusimaa.revontulet.widgets` created with it.
- `xcodegen generate` after the `project.yml` change; open the generated project.

## 1. Core tests (no device)

```bash
cd Packages/AuroraCore && swift test
```

Expect: the new Widgets tests pass on macOS (and on Linux in CI): snapshot builder, refresh policy,
municipality names. They must have been seen failing before the implementation (constitution IV).

## 2. Shared store and migration

Run the app unit tests in the simulator. Expect: migration copies once and never overwrites;
selection copied; app and a second store instance on the same suite see each other's writes.

## 3. Artwork spike and all layouts (simulator)

1. Run the `RevontuletWidgets` scheme; pick each family in the widget gallery. Expect a sample, clearly
   a sample (US3-3).
2. Put the app in each of the four levels with the stub scenarios and add small and medium widgets.
   Expect the level word, reason, place and age matching the main screen (US1, SC-002) and the app's
   curtains behind them, strength by level.
3. Check legibility against the draft: the level word is the clearest element at the 5 px blur;
   curtains behind the small widget's level word stay legible.
4. Light and dark Home Screen, tinted and clear icon styles: level readable without colour
   (FR-006, FR-024).
5. Largest accessibility text size, Finnish, Swedish and English: no clipped level word, no overlap
   (SC-005).
6. VoiceOver: each family reads the one-sentence label (FR-016).

## 4. States

- Fresh install, no result: "Open Revontulet to choose a place", no level, nothing fetched (US3-2,
  US4-3). Check the network log.
- Stale: advance the clock past 30 min (stub clock) or wait: dimmed sky, "Old data", age (US3-1).
- Airplane mode with cache: last result, honestly marked, never blank (US3, SC-004).
- Station without valid R: the app's no-data wording (US3-4).
- Out of coverage place: the app's out-of-coverage wording.

## 5. Refresh behaviour (simulator, then the phone)

1. Add one widget of each family. Trigger reloads together (Xcode's widget reload, or the debug menu
   in Settings of the scheme). Expect one magnetometer request in the network log, not five (US4,
   FR-020).
2. With fresh data in the shared cache, reload again: no request.
3. Open the app, change place: return to the Home Screen; widgets show the new place within 5 s
   (US4-5, SC-003).
4. Leave the app closed during an evening after dusk in season: the widget's data time advances; the
   age label never claims fresher data than it has (US4-1, SC-008).
5. Low Power Mode: widgets fall back to the stale look as data ages (US4 independent test).

## 6. Privacy and review gates

- The extension has no location usage: no location prompt, no location keys in its Info.plist and
  no `CL*` symbols in its binary (FR-014). `libswiftCoreLocation` does appear in `otool -L`:
  `import SwiftUI` autolinks it in the iOS 26 SDK, so every SwiftUI widget carries it.
- Network log shows only the FMI/NOAA hosts the app already uses; no analytics.
- Archive build: the privacy report lists no collected data beyond the alerts' coarse zone; the
  extension has its own `PrivacyInfo.xcprivacy` (SC-007).
- Xcode Cloud export succeeds with the new App ID and App Group (no exit 70).
