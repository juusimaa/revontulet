# Contract: New Data Inputs (NOAA SWPC and FMI forecast)

What the core fetches for this feature, and how it reads it. Every URL is fixed: no parameter
depends on the user, the place or the zone (FR-018). Verified live on 2026-10-26
([research.md R1–R3, R5](../research.md)). SWPC changes products without notice, so every
parser decodes tolerantly and any failure (HTTP error, 404, decode error) makes only its own
input unavailable (FR-020).

| Input | URL | Refetch at most | Size (gzip) |
|---|---|---|---|
| Propagated solar wind, last hour | `https://services.swpc.noaa.gov/products/geospace/propagated-solar-wind-1-hour.json` | every 5 min | ~2 KB |
| Kp forecast | `https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json` | every 60 min | ~0.5 KB |
| Alerts, watches, warnings (30 days) | `https://services.swpc.noaa.gov/products/alerts.json` | every 60 min | ~6 KB |
| FMI cloud forecast, all zones | see [below](#fmi-cloud-forecast) | every 3 h | ~15 KB |

The app sends `Accept-Encoding: gzip` (existing `URLSessionHTTPClient`). SWPC serves
`max-age=60`, and its `ETag`/`Last-Modified` change every minute even when the content does
not, so conditional requests are not used. After a failure, the next attempt is on the next
refresh (≥ 1 minute later, as NWS asks).

## Propagated solar wind

Array of arrays; the first row is the header. Columns are found **by name**, not position.

```json
[["time_tag","speed","density","temperature","bx","by","bz","bt","vx","vy","vz","propagated_time_tag"],
 ["2026-10-26T18:53:00Z",366.5,5.12,82970.0,6.77,-4.33,3.82,8.92,-366.3,2.9,-11.3,"2026-10-26T19:53:15Z"]]
```

| Column | → `SolarWindSample` | Notes |
|---|---|---|
| `time_tag` | `time` | UTC, minute observed at L1 |
| `propagated_time_tag` | `arrival` | Modelled arrival at Earth |
| `bz` | `bz` | nT, GSM (matches SWPC's active spacecraft's `bz_gsm`) |
| `speed` | `speed` | km/s |
| `density` | `density` | cm⁻³ |

`null` → nil. Rows without `time_tag` are dropped. Duplicate minutes keep the last row. A
header without `time_tag`, `bz`, `speed` or `propagated_time_tag` is a decode error.

## Kp forecast

Array of objects (SWPC switched from array-of-arrays in 2026; the parser also accepts the old
shape with a header row, mapped by the same names).

```json
{"time_tag": "2026-10-27T00:00:00", "kp": 3.0, "observed": "predicted", "noaa_scale": null}
```

| Field | → `KpBlock` | Notes |
|---|---|---|
| `time_tag` | `start` | UTC without `Z`; start of a 3-hour block |
| `kp` | `kp` | Decimal (thirds), 0…9 |
| `observed` | `kind` | `observed`, `estimated`, `predicted`; unknown values → `predicted` |
| `noaa_scale` | — | Not used |

The file holds about a week of past blocks and about 2.5 days of predicted blocks, which covers
tonight and tomorrow night in Finland. `KpForecast.fetchedAt` is the fetch time, shown in the
details as "updated".

## Storm watches (from alerts.json)

Array of `{product_id, issue_datetime, message}`; `issue_datetime` is UTC
`yyyy-MM-dd HH:mm:ss.SSS`; `message` is free text with mixed line endings.

A message is a **geomagnetic storm watch** when it contains
`Space Weather Message Code: WATA\d\d` (WATA20 = G1, WATA30 = G2, WATA50 = G3 seen; the G level is
read from the day lines, not the code, so unknown codes still work). `product_id` is not used.

Example (verbatim):

```text
Space Weather Message Code: WATA20
Serial Number: 1132
Issue Time: 2026 Oct 20 1912 UTC

WATCH: Geomagnetic Storm Category G1 Predicted
Highest Storm Level Predicted by Day:
Oct 21:  G1 (Minor)   Oct 22:  None (Below G1)   Oct 23:  None (Below G1)
THIS SUPERSEDES ANY/ALL PRIOR WATCHES IN EFFECT
```

Parsing:

1. **Issue time** from `Issue Time: yyyy MMM dd HHmm UTC`; fall back to `issue_datetime`.
2. **Kind**: a line starting `CANCEL WATCH:` is a cancellation, `WATCH:` a watch.
3. **Day levels**: every match of `([A-Z][a-z]{2}) ?(\d{1,2}) *: *(G[1-5]|None)` after the
   `Highest Storm Level Predicted by Day:` or `Cancelled Level Predicted:` line. Days have no
   year: use the issue year, plus one if the month is more than six months before the issue
   month (December → January).
4. **Current watch state**: take the newest watch; apply, in issue order, every later
   cancellation's day levels on top of it. Days with `None` or before today (UTC) are dropped.
   Older watches are ignored (each watch supersedes all earlier ones).
5. Result: one `StormWatch` per remaining G level, with its days and issue time.

A message that matches the code but none of the patterns is skipped; it never fails the whole
file.

## FMI cloud forecast

One request for all ten zone positions (repeated `latlon` works; verified), so it is the same
for every user:

```text
https://opendata.fmi.fi/wfs?service=WFS&version=2.0.0&request=getFeature
  &storedquery_id=fmi::forecast::edited::weather::scandinavia::point::simple
  &latlon=69.756,27.007&latlon=69.058,20.775&… (all ten station positions, from stations.json)
  &parameters=TotalCloudCover&timestep=60
```

- Response: BsWfs simple features; ~72 hourly values per point (three days), `TotalCloudCover`
  in percent, `NaN` → missing. Parsed with the existing `BsWfsParser`; each `gml:pos` is matched
  to the nearest zone position (within 1 km).
- FMI sends `Cache-Control: max-age=21600`; the app refetches at most every 3 hours.
- Licence: FMI open data, CC BY 4.0, as today.

## Attribution

Details show "NOAA Space Weather Prediction Center" next to FMI and Statistics Finland. NWS
material is public domain; no NOAA or NWS logo is used, and nothing suggests endorsement
(R12).
