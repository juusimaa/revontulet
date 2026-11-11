# Contract: Widget refresh and timeline

How the extension decides what to show and when to reload, and how the app nudges it. The rules
live in [widget-core-api.md](widget-core-api.md); this file is the shell's wiring.

## Provider flow (per timeline request, `getTimeline`)

```text
1. selection = shared PlaceSelectionStore.selection
   cached    = shared result cache.load()
2. place:
     municipality(code)  -> Place(manual:) built from MunicipalityNames (representative point)
     currentLocation     -> cached?.place (never a location request)
     none available      -> state = noPlace; no fetch; next reload in 60 min (FR-021)
3. if WidgetRefreshPolicy.resultNeedsFetch(cached, place, now):
       try AuroraService.refresh(for: place, at: now, force: false)   // writes the cache on success
     on offline / no data / error: keep `cached`; the entry is built from it (FR-020, FR-022)
4. if family == systemMedium and WidgetRefreshPolicy.outlookNeedsFetch(...):
       OutlookService.refresh(for: place, zoneID:, at: now, force: false)
5. snapshot = WidgetSnapshot.make(result, outlook, now)
6. entries:
     [ Entry(date: now, state: stale? ? .stale : .current) ]
     + Entry(date: staleMoment(measuredAt), state: .stale)   if still in the future
7. policy: .after(WidgetRefreshPolicy.nextReload(after: now, at: place.coordinate))
```

Rules:

- All fetching goes through one `WidgetDataLoader` actor so concurrent requests for the five
  families share one fetch (R7). Requests made while a load runs wait for it.
- `force` is always false. A widget never bypasses the core's intervals.
- Time budget: the provider returns the cached entry immediately if the fetch has not finished when
  the system's allowance is nearly used; the fetch task is cancelled and writes nothing.
- `getSnapshot`: with data, the current entry; in the gallery (`context.isPreview`), the sample
  state. `placeholder`: a redacted layout with the sample.
- Out-of-coverage and no valid R values map to `noData` with the same wording as the app. When the
  place is `currentLocation` and the cached place is outside coverage, the app never stored a
  result, so the widget shows `noPlace`.

## App to widget

- After `MainScreenModel` stores a result (`state = .result`), and after the selection changes, the
  app calls `WidgetCenter.shared.reloadAllTimelines()`.
- It skips the call when the new result equals the previous in level, reason, municipality and
  `measuredAt`.
- The app never schedules a background task for widgets and never fetches on their behalf.

## Tap behaviour

- No `widgetURL`. A tap opens the app on its main screen; Lock Screen widgets ask for unlock first.

## Accessibility contract (per family)

Each entry sets one VoiceOver label of the form
`"<Level>, <reason>, <place>, <age>"` in the system language (stale: `"Old data, <age>, last
level <Level>, <reason>, <place>"`), and hides the artwork and glyph from VoiceOver. Dynamic Type
applies where the family allows it; the level word is never truncated, reason and place truncate
last-in-first-out (place first).

## Rendering contract

- Containers use `containerBackground(for: .widget)`; Home Screen widgets draw the sky there.
- Lock Screen families use no custom background and system vibrancy (`AccessoryWidgetBackground`
  for the circular one).
- In accented and vibrant modes the level word, gauge and glyph are accentable; the artwork is
  not. Stale dims the artwork to 20% of its level strength and the text stays at full contrast.
