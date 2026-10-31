# Contract: Main Screen Additions

Extends [spec 001's main screen states](../../001-aurora-main-screen/contracts/main-screen-states.md).
Visual design is done with the `ios-ui-craft` skill (Principle VI); this file fixes only what
each element must show and when. All text exists in fi, sv and en (FR-023).

## Content

| Element | Where | When |
|---|---|---|
| Headline, place, station, data age | unchanged | unchanged |
| **Soon line**: "Activity likely to rise within about 45 minutes" | Directly under the headline, visibly secondary and marked as a forecast (e.g. a "Soon" label) | State Possible or Likely and not hidden by the light rule ([soon-rules.md](soon-rules.md#display-fr-008-to-fr-010)) |
| **Outlook**: two rows, "Tonight" and "Tomorrow night", each "<Level> – <reason>" | Below the headline block, under a "Forecast" heading | A place inside coverage |
| **Moon** in details: "Moon 85 %, waxing gibbous, up" / "below the horizon" | Details panel, next to darkness | Always with a result |
| **Solar wind** in details: state, Bz, speed, density, data age | Details panel | Always; "unavailable" when Unknown |
| **Outlook details**: per night expected activity, max Kp, storm watch, darkness, moon, mean cloud cover, update times, "This is a forecast, not a measurement" | Details of the outlook rows | When the outlook is shown |
| **Attribution**: "NOAA Space Weather Prediction Center" added to FMI and Statistics Finland | Details | Always (FR-021) |

Rules:

- The headline stays the largest and first element; nothing new is placed above it (SC-006).
- Forecast elements never use the headline's level styling at the same size, so a forecast is
  never mistaken for a measurement (FR-009, SC-005).
- Once tonight's dark period has started, the row is titled **"Rest of tonight"** (VoiceOver:
  "Forecast for the rest of tonight: …"), because it covers only the hours from now on
  ([outlook-rules.md](outlook-rules.md#1-nights)).
- If that row's expected activity is lower than the headline's measured activity, the row adds
  **"Activity now is higher than forecast"**. Only that way round: a forecast above the
  measurement may still come true later in the night. The forecast level itself never takes the
  measurement into account (FR-009).
- Levels are text, never colour alone. VoiceOver reads the soon line as "Forecast: …" and each
  outlook row as "Forecast for tonight: …".
- Each factor row in both details (activity, storm watch, darkness, moon, clouds, solar wind)
  carries an effect badge, a symbol and a word, following [chance-rules.md](chance-rules.md):
  **Helps** (probable activity, a storm watch, Dark, no bright moon, Clear, soon Possible or
  Likely), **Limits** (unlikely activity, Twilight, a bright moon, Partly cloudy) or
  **Prevents** (Too light, Overcast). Possible activity, no watch, Quiet or Unknown solar wind
  and cloud cover not included show no badge. The storm watch row is titled "Geomagnetic storm
  watch" so it is not read as a weather warning.

## States

| State | Soon line | Outlook rows |
|---|---|---|
| Loading (first run) | hidden | hidden |
| Result, inputs fresh | per rules | per rules |
| Soon Unknown | hidden; details say "Solar wind data unavailable" | unaffected |
| Outlook unavailable | unaffected | one row "Outlook unavailable" |
| Offline (all fetches failed) | from the cached snapshot if the newest sample is ≤ 20 min old, else hidden | from cached inputs, recomputed for now; "unavailable" if no Kp forecast is cached or it no longer covers tonight |
| Headline No data (no R) | hidden | still shown (it does not need R) |
| Location denied / outside coverage | hidden | hidden |

## Refresh

`OutlookService.refresh` runs on the same triggers as the headline refresh (launch, foreground,
every 5 minutes in the foreground, pull to refresh). The service decides what is due (R8).
