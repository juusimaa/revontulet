# Research: Aurora Main Screen

**Feature**: [spec.md](spec.md) | **Date**: 2026-10-22

All findings were checked against live FMI and Statistics Finland services on 2026-10-22 unless
marked UNVERIFIED.

## R1. Definition of FMI's R value

**Decision**: Compute R on the device from FMI open magnetometer data, using FMI's published
definition:

- Input: 10-second averages of the X, Y and Z field components (`MAGN{X,Y,Z}_PT10S_AVG`, nT,
  baseline already removed).
- Window: the 10 minutes before the calculation time (60 consecutive 10 s samples), sliding,
  recalculated every 5 minutes.
- Activity: absolute differences between consecutive samples, summed over X, Y and Z; samples in
  the most recent 5 minutes weigh twice as much as older ones; weighted average; instrument noise
  floor subtracted.
- Scaling: R / 1350 = nT/s.

Working formula (empirical fit, RMSE ≈ 1.3 on 350 station × time samples against FMI's published
values):

```
R ≈ 45 · Σ wᵢ (|ΔXᵢ| + |ΔYᵢ| + |ΔZᵢ|) / Σ wᵢ − 1.5
    wᵢ = 2 for the newest 30 differences, 1 for the older 30
```

45 = 1350 / (3 components × 10 s), which matches FMI's nT/s scaling. The −1.5 approximates the
noise-floor subtraction. Negative results are clamped to 0. The exact noise floor per station is
UNVERIFIED; the scale factor and offset are constants in one place and are re-fitted from recorded
reference data (see R2).

Verified in `RIndexTests` (2026-10-22, 350 points, 10 stations, 3 h): RMSE 1.36, max error 2.7,
with `scale = 45` and `offset = 1.5` unchanged. Time alignment: FMI labels R with the end of the
last 10 s averaging interval, so R at time T uses the 61 samples at T − 610 s … T − 10 s (ending
the window at T itself gives max error 14). The app shows R's time as the newest sample + 10 s.

**Rationale**: Principle I (open data only). The user chose this over FMI's undocumented chart
endpoint (see R2).

**Alternatives considered**:
- FMI chart endpoint `cdn.fmi.fi/apps/magnetic-disturbance-observation-graphs/serve-data.php`
  (exact official R for all 12 stations, tiny JSON). Rejected for runtime use: not part of FMI's
  open data service, undocumented, stability and terms unknown (Principle I).
- Older space.fmi.fi "RX = hourly max − min of X" index. Rejected: a different product from what
  fmi.fi shows now.

Source: <https://www.ilmatieteenlaitos.fi/avaruussaatiedotuksen-tulkintaohje>

## R2. Reference data for testing

**Decision**: During development only, a tool records matching pairs of (a) FMI open magnetometer
data and (b) FMI's published R values from the chart endpoint, and stores them as test fixtures.
The shipped app never calls the chart endpoint. A request to FMI asking whether the chart data may
be used directly is a follow-up outside this feature.

**Rationale**: SC-003 needs ground truth; the published values are the only ground truth. Using
them offline for tests keeps the runtime on open data only.

Note: the chart endpoint's timestamps are Finnish local time encoded as UTC; the recording tool
must convert them. The latest point can be partial and must be skipped.

## R3. Activity levels and thresholds

**Decision**: Three activity levels per station, matching fmi.fi's "Aktiivisuus nyt" map, plus a
missing-data state:

| Level | fmi.fi label (fi) | Rule |
|---|---|---|
| Unlikely | Revontulet epätodennäköisiä | R < yellow |
| Possible | Revontulet mahdollisia | yellow ≤ R < red |
| Probable | Revontulet todennäköisiä | R ≥ red |
| No data | Viimeisin mittaus puuttuu | no valid R |

Per FMI, the yellow threshold is ≈ 50 % chance of faint aurora and red ≈ 50 % chance of bright or
widespread aurora. Thresholds are per station and bundled with the app:

| Code | Station | Lat | Lon | Yellow | Red |
|---|---|---|---|---|---|
| KEV | Kevo | 69.756 | 27.007 | 55 | 165 |
| KIL | Kilpisjärvi | 69.058 | 20.775 | 61 | 210 |
| IVA | Ivalo | 68.559 | 27.289 | 72 | 275 |
| MUO | Muonio | 68.022 | 23.520 | 75 | 300 |
| PEL | Pello | 66.904 | 24.080 | 73 | 285 |
| RAN | Ranua | 65.896 | 26.409 | 70 | 240 |
| OUJ | Oulujärvi | 64.511 | 27.227 | 68 | 200 |
| MEK | Mekrijärvi | 62.774 | 30.968 | 64 | 150 |
| HAN | Hankasalmi | 62.254 | 26.597 | 63 | 140 |
| TAR | Tartu (Estonia) | 58.264 | 26.460 | 55 | 100 |

Excluded: Nurmijärvi (NUR) and Sodankylä (SOD) have thresholds on fmi.fi but no data in FMI open
data; Masi (Norway) is in the open data feed but has no FMI threshold. Southern Finland is
therefore served by Hankasalmi or Tartu.

**Rationale**: FR-001a requires FMI's levels; thresholds are FMI's own values.

Thresholds were read from the fmi.fi chart page on 2026-10-22; re-check them when recording
fixtures.

## R4. Magnetometer data access

**Decision**: One request per refresh for all stations:

- Stored query `fmi::observations::magnetometer::simple` on `https://opendata.fmi.fi/wfs`.
- `bbox=5,50,40,80`, `parameters=MAGNX_PT10S_AVG,MAGNY_PT10S_AVG,MAGNZ_PT10S_AVG`,
  `starttime` = now − 12 min (rounded down to 10 s), `endtime` = now.
- Stations are identified by matching `gml:pos` to the bundled station table (the simple format
  has no station names). Values may be `NaN`; a window with gaps of more than 3 samples gives no R.
- Data latency is about 1 minute. Refresh every 5 minutes while the app is in the foreground.

**Rationale**: Requesting all stations sends no location information at all (Principle II) and
lets the app fall back to the next-nearest station with data (FR-005). Measured size ≈ 1.5 MB
uncompressed, tens of KB gzipped (URLSession decompresses automatically).

**Alternatives considered**: requesting only the nearest station's `fmisid` (smaller, but reveals
which station area the user is in and needs a second request on outage).

## R5. Cloud cover

**Decision**: Observations from all Finnish weather stations in one request:

- Stored query `fmi::observations::weather::simple`, `bbox=19,59.5,32,70.1`,
  `parameters=TotalCloudCover`, a 30-minute window ending now; keep the latest value per station.
- Units: octas 0–8. Value 9 (sky obscured, e.g. fog) and `NaN` are treated as unknown.
- About 106 stations, every 10 minutes, ~10–15 min latency; response ~3–6 KB gzipped; server sends
  `max-age=600`. Refresh at most every 10 minutes.
- On the device, use the nearest station with a valid value within 100 km; otherwise cloud cover
  is unknown (spec edge case: shown as "not included").

**Rationale**: No location information leaves the device (FR-011); one small request covers all of
Finland.

**Alternatives considered**:
- Point forecast `fmi::forecast::edited::weather::scandinavia::point::simple` with `latlon`
  rounded to 0.1°. Better in sparse Lapland, but sends user-derived coordinates and adds a second
  source. Kept as a possible later improvement.
- MEPS/edited grids (GRIB2/NetCDF, 98–854 KB): no decoder on iOS; rejected.
- Satellite cloud products: none in FMI open data.

## R6. Darkness

**Decision**: Compute the sun's elevation on the device with the NOAA solar position algorithm (no
data source needed):

| Sun elevation | Darkness |
|---|---|
| > −6° | Too light (day or civil twilight) |
| −12° … −6° | Twilight (nautical) |
| ≤ −12° | Dark |

**Rationale**: Deterministic, offline, testable against published NOAA values.

## R7. Combining activity, darkness and clouds (FR-001d)

**Decision**: The documented rule is in [contracts/chance-rules.md](contracts/chance-rules.md).
In short: the activity level gives a starting level (Unlikely → Low, Possible → Moderate,
Probable → High); "too light" or 7–8 octas of cloud set it to None; twilight or 4–6 octas each
lower it by one level; the limiting factor is reported.

**Rationale**: Simple, explainable in one sentence, and fully covered by table-driven tests
(SC-003a).

## R8. Municipalities, place name and coverage

**Decision**: Bundle Statistics Finland's 2026 municipality boundaries, 1:1,000,000 layer
(`tilastointialueet:kunta1000k_2026`, 308 municipalities, Finnish and Swedish names), with
coordinates reduced to 4 decimals (~0.5 MB compressed). A build-time tool converts it to a compact
bundled file with a bounding box and a precomputed representative point (point on surface /
pole of inaccessibility) per municipality.

- Place name for current location: point-in-polygon on the device. If no polygon contains the
  point, the nearest municipality within 15 km is used (islands, boats, coastline generalisation);
  otherwise the location is outside coverage (FR-001e).
- Manual selection (FR-010): search the bundled list by Finnish or Swedish name; the
  representative point is used for darkness, cloud cover and the nearest station.
- Licence: CC BY 4.0. Attribution: "Municipality boundaries: Statistics Finland, CC BY 4.0"
  (plus "contains data from the National Land Survey of Finland" as a safeguard).

**Rationale**: Gives place names and the Finland coverage test without any network request and
without sending coordinates anywhere (FR-003, FR-011).

**Alternatives considered**:
- 1:4,500,000 layer (88 KB): misplaces Tornio centre and Suomenlinna; rejected for accuracy.
- Apple reverse geocoding: sends coordinates to Apple; rejected (Principle II).

Sources: `https://geo.stat.fi/geoserver/tilastointialueet/wfs`,
<https://stat.fi/en/about-us/get-to-know-statistics-finland/legislation/terms-of-use>

Known limitation: a user just across the border (e.g. Haparanda) is within 15 km of Tornio and is
treated as being in Tornio. This is harmless for aurora visibility.

## R9. Licences, attribution and limits

- FMI open data: CC BY 4.0. Attribution shown in the app: "Source: Finnish Meteorological
  Institute (FMI), CC BY 4.0". FMI prescribes no exact wording (UNVERIFIED).
- FMI limits: 20,000 download requests/day and 600 requests per 5 minutes; no API key needed.
  Whether limits are per client IP is UNVERIFIED. The app makes at most ~12 magnetometer + 6 cloud
  requests per hour while in the foreground and none in the background, far below the limits.

## R10. Portability of the core (Principle III)

**Decision**: The core is a SwiftPM package with no Apple-only imports.

- Official Swift SDK for Android exists since Swift 6.3; 6.4.1 matches the project toolchain.
- Use `#if canImport(FoundationNetworking)` for URLSession.
- Do not use `XMLParser` (FoundationXML / libxml2 availability on Android is UNVERIFIED): FMI's
  `simple` format is flat, so the core uses a small purpose-built parser for `BsWfsElement`s.
- No Combine, CoreLocation, os.log, SwiftUI, UserDefaults in the core; location is passed in as
  plain latitude/longitude; caching goes through a protocol implemented by each platform.
- Bundled data files are package resources (`Bundle.module`), which SwiftPM supports on Linux and
  Android.

## R11. Platform and tooling

- Xcode 27.1, Swift 6.4, Swift 6 language mode with strict concurrency.
- iOS deployment target 26.0 (Liquid Glass).
- Tests: Swift Testing for the core; XCTest UI tests for main screen flows.
- UI design and implementation use the `ios-ui-craft` skill (Principle VI).
- Localisation: one String Catalog with fi, sv and en; English is the development language.
