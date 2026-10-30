# Contract: "Soon" Rules

The fixed rule for FR-006 to FR-010: the "soon" state from real-time solar wind. It is computed
in `AuroraCore` (`SoonCalculator`), is stateless apart from the previous state passed in, and
never changes the headline chance (FR-009). Tests cover every reference case (SC-003 uses the
recorded nights in [research.md R6](../research.md)).

## Inputs

| Input | Values | Source |
|---|---|---|
| Solar wind samples | 1-minute samples observed at L1: time, modelled arrival time at Earth, Bz (GSM, nT), speed (km/s), density (cm⁻³); any value may be missing | NOAA SWPC propagated solar wind, last hour ([noaa-data.md](noaa-data.md)) |
| Band | North, Central, South | The place's zone ([Bands](#bands)) |
| Now | Date | Clock |
| Previous state | Soon state or none | Last result for the same place |

## Rule

1. **Window**: the 20 minutes (L1 time) ending at the newest sample that has both Bz and speed.
2. **Unknown** if that newest sample was observed more than 20 minutes before now (the product
   normally runs about 8 minutes behind), or fewer than 15 of
   the window's 20 minutes have both Bz and speed. Stop.
3. **Coupling** per minute: `Ey = speed × max(0, −Bz) / 1000` (mV/m), the dawn–dusk electric
   field of the solar wind. Southward Bz with fast wind drives substorms; northward Bz gives 0.
4. **Driver** = the **median** of the window's per-minute Ey. The median needs more than half of
   the window to be strong, so a short spike does not trigger the rule (FR-007).
5. **State** from the band's thresholds:
   - Driver ≥ `likely` → **Likely**
   - Driver ≥ `possible` → **Possible**
   - otherwise **Quiet**
6. **Hysteresis**: if the previous state was higher than the new one, the previous state is kept
   while the driver is at least 75% of the previous state's threshold, so the line does not
   flicker.
7. **Arrival window** (Possible or Likely only): the first minute of the window whose Ey meets the
   state's threshold; time remaining = its modelled arrival time − now, rounded to the nearest
   15 minutes, at least 15 minutes. Shown as "within about N minutes", or "within about an
   hour" for 60 minutes or more. SWPC's propagation (43–72 minutes in a week of data, R1)
   replaces any estimate from the speed. The density is shown in the details only and is not
   part of the rule (R6).

## Thresholds (initial, calibrated in R6)

| Band | `possible` (mV/m) | `likely` (mV/m) |
|---|---|---|
| North | 1.5 | 3.0 |
| Central | 2.5 | 5.0 |
| South | 4.0 | 8.0 |

For reference: 400 km/s with Bz −5 nT gives 2.0 mV/m, 600 km/s with Bz −10 nT gives 6.0 mV/m.
The final values are fixed in `SoonCalculator` and this table before release. Any later change
is a change to the feature.

## Bands

| Band | Zones (station codes) |
|---|---|
| North | KEV, KIL, IVA, MUO, PEL |
| Central | RAN, OUJ, MEK, HAN |
| South | TAR |

The same bands are used by the Kp mapping in [outlook-rules.md](outlook-rules.md).

## Display (FR-008 to FR-010)

| State | Main screen | Details |
|---|---|---|
| Likely | "Activity likely to rise <window>"; if the headline activity is Probable: "Activity likely to continue" | State, Bz, speed, density, data time |
| Possible | "Activity may rise <window>"; if the headline activity is Probable: "Activity may stay high" | same |
| Quiet | nothing | "No sign of rising activity" (if headline activity is Probable: "No sign of further rise") |
| Unknown | nothing | "Solar wind data unavailable" with the age of the last data, if any |

The main-screen line is hidden when it is too light now **and** at now + time remaining
(FR-010). When the headline is None because of overcast, the line is shown with the note
"overcast now".

## Reference cases (must pass)

All with band North, previous state none, newest sample observed 8 minutes before now, 20 of 20
minutes valid, and every sample arriving 55 minutes after it was observed, unless stated.

| # | Window | Expected |
|---|---|---|
| 1 | Bz −6, speed 450 throughout (Ey 2.7) | Possible; first strong minute arrives 55 − 8 − 19 = 28 min from now → "within about 30 minutes" |
| 2 | Bz −8, speed 500 throughout (Ey 4.0) | Likely, "within about 30 minutes" |
| 3 | Bz +5 throughout | Quiet, no window |
| 4 | Bz −20 for 5 minutes, +3 for 15 | Quiet (median 0) |
| 5 | Bz +2 for the first 9 minutes, then Bz −8, speed 500 for 11 | Likely; first strong minute arrives 55 − 8 − 10 = 37 min → "within about 30 minutes" |
| 6 | Newest sample observed 21 minutes before now | Unknown |
| 7 | 14 of 20 minutes valid | Unknown |
| 8 | Same as 2, band South | Possible (4.0 ≥ 4.0, < 8.0) |
| 9 | Previous Likely, driver 2.4 (≥ 0.75 × 3.0 = 2.25) | Likely (hysteresis) |
| 10 | Previous Likely, driver 2.0 | Possible |
| 11 | Same as 2, arrival 30 minutes after observation | 30 − 8 − 19 = 3 min → "within about 15 minutes" (minimum) |
| 12 | Same as 2, arrival 80 minutes after observation | 80 − 8 − 19 = 53 min → 60 → "within about an hour" |
