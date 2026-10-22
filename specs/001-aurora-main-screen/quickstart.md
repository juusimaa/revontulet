# Quickstart: Validate the Aurora Main Screen

How to prove the feature works end to end. Details of types and rules are in
[data-model.md](data-model.md) and [contracts/](contracts/).

## Prerequisites

- macOS with Xcode 27.1 (Swift 6.4), iOS 26+ simulator or device.
- Python 3 (only for the data tools in `tools/`).
- Network access to `opendata.fmi.fi` (live checks only; tests use recorded fixtures).

## 1. Core package: unit and reference tests

```sh
cd Packages/AuroraCore
swift build
swift test
```

Expected:
- All chance rule reference cases pass ([contracts/chance-rules.md](contracts/chance-rules.md)) — SC-003a.
- R values from recorded magnetometer fixtures are within ±3 of FMI's published values, and the
  activity level matches FMI in every case where FMI's R is more than 3 away from a threshold
  (≥ 20 cases) — SC-003.
- Solar elevation matches NOAA reference values within 0.5°.
- Place resolution: Helsinki, Suomenlinna, Tornio, Hailuoto, Mariehamn, Utsjoki resolve to the
  right municipality; a point in central Sweden and one in the open Baltic are outside coverage.

The core builds without the app target (Principle III).

## 2. Refresh data files (only when needed)

```sh
python3 tools/build-municipalities.py      # regenerates bundled municipalities (Statistics Finland)
python3 tools/record-fixtures.py           # records new magnetometer + reference R fixtures
```

`record-fixtures.py` is a development tool; the app never calls the chart endpoint it uses.

## 3. App: UI tests

```sh
xcodebuild test -project Revontulet.xcodeproj -scheme Revontulet \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

UI tests run against a stubbed HTTP client and fixed location, and cover: result state, offline
with cache, location denied → choose municipality, outside coverage, and relaunch keeps the chosen
municipality.

## 4. Manual end-to-end check (simulator)

1. Run the app; set the simulator location to Rovaniemi (66.50, 25.73). Expected: within a few
   seconds the screen shows a chance level with a reason, "Rovaniemi", station Ranua or Pello with
   distance, and the measurement age. Compare the activity level with the
   [fmi.fi aurora map](https://www.ilmatieteenlaitos.fi/revontulet-ja-avaruussaa).
2. Quit and relaunch with the network disabled. Expected: the last result appears immediately,
   with an offline message; after 30 min it is marked outdated.
3. Reset location permissions and deny access. Expected: location-denied state; choose
   "Utsjoki" from the list; the result is for Utsjoki and marked as manually chosen; relaunch
   keeps it.
4. Set the location to Stockholm (59.33, 18.07). Expected: outside coverage state.
5. Switch the device language to Finnish and to Swedish. Expected: all text translated;
   "Helsingfors" shown for Helsinki in Swedish.
6. Turn on VoiceOver and the largest Dynamic Type size. Expected: level, reason, place, station
   and data age are read out and nothing is clipped.
7. Check the network log (e.g. Proxyman or Instruments). Expected: only the two FMI requests in
   [contracts/fmi-open-data.md](contracts/fmi-open-data.md), with no coordinates or
   location-derived values in them.
