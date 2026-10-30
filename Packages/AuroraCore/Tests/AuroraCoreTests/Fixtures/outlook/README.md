Recorded inputs for the aurora outlook (specs/003-aurora-outlook, research R4 and R10), written
by `tools/record-outlook-fixtures.py` and `tools/record-moon-reference.py` on 2026-10-30.

| File | Source | Notes |
|---|---|---|
| `solar-wind-quiet.json` | SWPC propagated solar wind, last hour | As returned; a quiet hour (Bz near 0, ~325 km/s) |
| `solar-wind-active.json` | derived from `solar-wind-quiet.json` | **Synthetic**: Bz turned southward by 10 nT, speed + 250 km/s, arrival times as recorded. Re-record on an active hour with `--only solar-wind --solar-wind-as active` |
| `solar-wind-gaps.json` | derived from the recorded hour | Nulls in Bz, speed and density, one row without `time_tag`, one duplicated minute whose second row has Bz + 1.5 |
| `kp-forecast.json` | SWPC Kp forecast | As returned (array of objects) |
| `kp-forecast-old-shape.json` | derived from `kp-forecast.json` | SWPC's earlier array-of-arrays shape with a header row, string values and a space in `time_tag` |
| `alerts.json` | SWPC alerts | Every WATA message (G1 and G2 watches, one G2 cancellation) and the first five others |
| `cloud-forecast.xml` | FMI `fmi::forecast::edited::weather::scandinavia::point::simple` | All ten station positions, TotalCloudCover, 60 min steps, as returned |
| `noaa-404.txt` | SWPC | The 404 body for the retired `products/solar-wind/mag-1-day.json` |
| `noaa-malformed.json` | derived | The recorded solar wind file cut off halfway |
| `moon-reference.json` | JPL Horizons | Moon elevation (topocentric, airless) and illuminated fraction at KEV, OUJ and TAR on 2026-03-15, 11-09 (new), 11-17, 11-24 (full) and 12-21 (polar night): 00/06/12/18 UTC plus the 10-minute step nearest each rise and set |

Calibration fixtures (`soon-nights/`, `kp-nights.json`) are written by `tools/calibrate-soon.py`
and `tools/calibrate-kp.py`; see research R6 and R7.

NOAA SWPC material is public domain; FMI open data is CC BY 4.0; JPL Horizons output is public
domain.
