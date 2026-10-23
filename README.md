<p align="center">
  <img src="Revontulet/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="Revontulet app icon" width="160" height="160" />
</p>

# Revontulet

Revontulet ("northern lights" in Finnish) is a native iOS app that shows the chance of seeing the
aurora borealis at your location in Finland.

The app computes FMI's R value, a measure of geomagnetic activity, on the device from the
Finnish Meteorological Institute's open magnetometer data. It classifies the value with FMI's
per-station thresholds, the same way [fmi.fi](https://www.ilmatieteenlaitos.fi/revontulet-ja-avaruussaa)
does, and combines it with darkness and cloud cover. The result is one of four levels (None, Low,
Moderate, High) with a short reason, such as "Low – overcast". The main screen also shows your
location, the nearest measurement station and how recent the data is.

<p align="center">
  <img src="docs/images/main-screen-oulu.png" alt="Main screen in Oulu on a dark, clear evening: the chance to see the aurora is High, with good conditions, measured at the Oulujärvi station 100 km away. The open details panel shows probable geomagnetic activity (R 309), a dark sky and clear weather" width="300" />
</p>

<p align="center"><sub>The main screen in Oulu during strong geomagnetic activity. The data in this
screenshot is synthetic.</sub></p>

> **Status:** early development. The first feature, the aurora main screen, is being built.
> See [specs/001-aurora-main-screen](specs/001-aurora-main-screen/).

## Principles

- **Open data only.** Science data comes from FMI open data and Statistics Finland (CC BY 4.0).
  There is no backend and no paid or scraped source.
- **Privacy by design.** Your location stays on the device. Network requests cover all of Finland
  and contain nothing derived from you. If you deny location access, you can pick a municipality
  by hand. No analytics, no tracking, no accounts.
- **Shared core, native shells.** All domain logic lives in the portable Swift package
  `AuroraCore`, which builds without Apple-only frameworks so that an Android version can follow.
  The SwiftUI app is a thin shell.
- **Languages.** Finnish, Swedish and English.

The full set of rules is in the [project constitution](.specify/memory/constitution.md).

## Repository layout

| Path | Contents |
|---|---|
| `Packages/AuroraCore` | Swift package with fetching, parsing, R calculation, chance rules, solar position, station selection, place resolution and caching |
| `Revontulet` | SwiftUI iOS app |
| `RevontuletUITests` | UI tests that run against a stubbed HTTP client |
| `tools` | Python scripts that regenerate bundled municipality data and record test fixtures |
| `specs` | Feature specifications, plans and task lists (Spec Kit) |
| `project.yml` | XcodeGen project definition |

## Requirements

- macOS with Xcode 27.1 (Swift 6.4)
- iOS 26 or later (iPhone)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Python 3, only for the scripts in `tools`

## Getting started

The Xcode project is generated from `project.yml` and is not committed. Change build settings in
`project.yml`, not in Xcode.

```sh
xcodegen generate
open Revontulet.xcodeproj
```

Run the core tests without the app:

```sh
cd Packages/AuroraCore
swift build
swift test
```

Run the UI tests:

```sh
xcodebuild test -project Revontulet.xcodeproj -scheme Revontulet \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

TestFlight builds come from Xcode Cloud. `ci_scripts/ci_post_clone.sh` installs XcodeGen,
generates the project, and sets the build number from `CI_BUILD_NUMBER`.

For the full validation steps, see the
[quickstart](specs/001-aurora-main-screen/quickstart.md).

## Data sources

- [FMI open data](https://en.ilmatieteenlaitos.fi/open-data): magnetometer and weather
  observations, CC BY 4.0
- [Statistics Finland](https://stat.fi/): municipality boundaries, CC BY 4.0

## License

[GNU Affero General Public License v3.0](LICENSE)
