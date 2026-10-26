# Contract: Outlook Rules

The fixed rule for FR-011 to FR-016: an outlook level for tonight and tomorrow night at a place.
Computed in `AuroraCore` (`OutlookCalculator`) from the Kp forecast, storm watches, the zone's
cloud forecast, the sun and the moon. The level itself comes from
[chance-rules.md](chance-rules.md), so an outlook and the headline can never disagree on how
the factors combine.

## Inputs

| Input | Source |
|---|---|
| Place (coordinate, zone, band) | Device; zone and band from [soon-rules.md](soon-rules.md#bands) |
| Now | Clock |
| Kp forecast: 3-hour UTC blocks with Kp and kind (observed, estimated, predicted) | NOAA SWPC ([noaa-data.md](noaa-data.md)) |
| Storm watches: G level and UTC days covered | NOAA SWPC alerts ([noaa-data.md](noaa-data.md)) |
| Cloud forecast for the zone: hourly total cloud cover (%) | FMI ([noaa-data.md](noaa-data.md#fmi-cloud-forecast)) |

## 1. Nights

- **Dark hours**: the times when Darkness is not Too light (sun at or below −6°), sampled every
  5 minutes, as in `SolarPosition`.
- **Tonight**: if it is not too light now, the dark period under way (from its start to its end).
  Otherwise the next dark period that starts within 24 hours. If none starts within 24 hours,
  tonight is **Too light**.
- **Tomorrow night**: the next dark period that starts after tonight ends and within 24 hours of
  that. If there is none, tomorrow night is **Too light**.
- A dark period is capped at 24 hours.
- **Relevant hours** of a night: its hours at **Dark** if it has any, otherwise all its dark hours
  (twilight only). For tonight under way, only the part from now on.

## 2. Expected activity

1. **Forecast Kp** = the highest Kp of all blocks that overlap the relevant hours (any kind:
   observed, estimated or predicted). With no overlapping block, expected activity is
   **unknown**.
2. **Watch Kp** = 4 + the highest G level of the watches whose UTC days overlap the relevant
   hours (G1 → 5 … G5 → 9). With no watch, none.
3. **Kp for the night** = the higher of the two (FR-013: a watch only raises it).
4. **Expected activity** from the band's thresholds:

| Band | Possible from Kp | Probable from Kp |
|---|---|---|
| North | 3 | 5 |
| Central | 4 | 6 |
| South | 5 | 7 |

Below "Possible from" → Unlikely. These are initial values: they are calibrated per band
against recorded nights in [research.md R7](../research.md) (SC-004) and then fixed here.

## 3. Sky for the night

- **Darkness**: Dark if the relevant hours reach Dark, otherwise Twilight.
- **Moon**: Bright if the moon is bright ([chance-rules.md](chance-rules.md)) for at least half of
  the relevant hours.
- **Clouds**: the mean of the zone's hourly cloud forecast over the relevant hours, converted to
  octas (`round(% × 8 / 100)`) and then to Clear, Partly or Overcast. If fewer than half of the
  relevant hours have a forecast value: Unknown.

## 4. Level and reason

`ChanceCalculator.chance(activity:darkness:moonBright:clouds:)` with the night's values gives the
level, limiting factor and reason. A night that is Too light gives **None – too light** without
needing any forecast.

Each night's outlook carries the highest storm watch G level (if any), the Kp forecast's and the
cloud forecast's fetch times, for the details (FR-016).

If expected activity is unknown and the night is not Too light, that night's outlook is
**unavailable** (FR-020).

## Display

| Case | Main screen | Details |
|---|---|---|
| Available | "Tonight: Moderate – geomagnetic storm watch" or "Tonight: Low – cloudy" | Expected activity, max Kp, watch, darkness, moon, mean cloud cover, update times, "This is a forecast" |
| Too light | "Tonight: None – too light" | Same, without activity |
| Unavailable | "Outlook unavailable" (once for both nights if both are) | Age of the last forecast, if any |

The reason is the chance reason, except that a watch replaces "some activity" or "good
conditions" with **"geomagnetic storm watch"** (`outlook.reason.stormWatch`) when the watch
decided the expected activity. Cloud cover not included is shown as for the headline.

## Reference cases (must pass)

Place at the Oulujärvi station (OUJ, band Central). Dates and Kp blocks are synthetic; the sun
and moon are computed for the date.

| # | Situation | Expected tonight |
|---|---|---|
| 1 | 2026-11-09 (new moon), max Kp 4 over the dark hours, mean cloud 10% | Moderate – some activity |
| 2 | Same, max Kp 6 | High – good conditions |
| 3 | Same, max Kp 2 | Low – low activity |
| 4 | 2026-11-24 (moon ~100% and up most of the night), max Kp 6, clear | Moderate – bright moon |
| 5 | 2026-11-09, max Kp 3, G2 watch for the UTC day (Kp 6) | High – geomagnetic storm watch |
| 6 | 2026-11-09, max Kp 6, mean cloud 95% | None – overcast |
| 7 | 2026-11-09, max Kp 6, no cloud forecast for the night | High – good conditions (cloud cover not included) |
| 8 | 2026-06-21 at Kevo (KEV) | None – too light, both nights |
| 9 | 2026-11-10 at 03:00 local (01:00 UTC, night under way), clear; Kp 6 in the 21–24 UTC block of 11-09, Kp 2 from 00 UTC on | Low – low activity (blocks that ended before now are ignored) |
| 10 | Kp forecast fetch failed, no cache, 2026-11-09 | Outlook unavailable |
