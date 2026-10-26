# Quickstart: Aurora Outlook

How to check that the feature works end to end. Rules and data are in
[contracts/](contracts/) and [data-model.md](data-model.md); this guide only lists what to run
and what to expect.

## Prerequisites

- Xcode 27.1, iOS 26 simulator; Docker for the Linux check (as for spec 002).
- Recorded fixtures in `Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/outlook/` (R10).

## 1. Core tests (macOS and Linux)

```sh
(cd Packages/AuroraCore && swift test)
docker run --rm -v "$PWD":/src -w /src/Packages/AuroraCore swift:6.4.1-noble swift test
```

Expect all tests to pass, including:

| Suite | Checks |
|---|---|
| `ChanceCalculatorTests` | chance-rules v2 reference cases 1–22 (SC-001) |
| `MoonPositionTests` | ≥ 20 reference times and places within 1° altitude and 2 points illumination (SC-002) |
| `SoonCalculatorTests` | soon-rules reference cases 1–12 |
| `SoonReplayTests` | recorded storm and quiet nights meet SC-003 |
| `KpMappingTests` | recorded nights meet SC-004 |
| `OutlookCalculatorTests` | outlook-rules reference cases 1–10 |
| `NOAAParserTests` | recorded NOAA responses, including gaps, fill values and a cancelled watch |
| `OutlookServiceTests` | fetch cadence (R8), independent failures, cache round trip |
| `ZoneEvaluatorTests` | zones include the moon; a moonlit Probable zone gives Moderate with `alert.body.brightMoon` |

## 2. Alert strings before 2.0 ships (R9)

```sh
xcodebuild test -scheme Revontulet -only-testing:RevontuletTests/AlertStringsTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expect the two `alert.body.brightMoon*` keys to exist in fi, sv and en (the test iterates
`AlertMessage.allKeys`). Commands run from the repository root.

## 3. App, with stubbed data

Run the new UI tests, which use `UITestHTTPClient` with recorded NOAA and FMI responses:

```sh
xcodebuild test -scheme Revontulet -only-testing:RevontuletUITests/OutlookUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

| Scenario (launch argument) | Expect |
|---|---|
| `-uitest-outlook storm` | Soon line "Activity likely to rise …", outlook "Tonight: High – geomagnetic storm watch" |
| `-uitest-outlook quiet` | No soon line; details "No sign of rising activity" |
| `-uitest-outlook moon` | Headline "Moderate – bright moon"; details show the moon as up |
| `-uitest-outlook noaa-down` | Headline as usual; no soon line; "Outlook unavailable" |
| `-uitest-outlook summer` | Outlook "None – too light" for both nights |

## 4. Live check on a device

1. Open the app in Oulu (GPX `Oulu.gpx`) in the evening.
2. Compare the details' Bz and speed with the SWPC real-time solar wind page; the data age is at
   most a few minutes.
3. Compare tonight's max Kp with the SWPC 3-day forecast for the same UTC blocks.
4. Turn on Airplane mode and relaunch: the soon line and outlook appear from cache within 1 s
   (SC-008), and the outlook still says "Tonight" correctly.
5. Check the details' attribution lists NOAA SWPC.

## 5. Alert service

Run the server tests (`cd Server && swift test`). Expect `ZoneEvaluator` results with the moon
and no NOAA requests from the service (FR-025): the stub HTTP client fails the test on any
request to `services.swpc.noaa.gov`.
