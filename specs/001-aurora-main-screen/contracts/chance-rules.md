# Contract: Chance-to-See Rules

The fixed, documented rule for FR-001 and FR-001d. Tests in the core package cover every row
(SC-003a). Any change to this table is a change to the feature and must update the spec.

## Inputs

| Input | Values | Source |
|---|---|---|
| Activity | Unlikely, Possible, Probable | Station R vs. thresholds ([research.md R3](../research.md)) |
| Darkness | Too light, Twilight, Dark | Sun elevation ([R6](../research.md)) |
| Clouds | Clear (0–3 octas), Partly (4–6), Overcast (7–8), Unknown (9, NaN, no station ≤ 100 km) | Nearest weather station ([R5](../research.md)) |

If there is no valid activity value, no chance is calculated (main screen shows the no-data state).

## Rule

1. Starting level from activity: Unlikely → **Low**, Possible → **Moderate**, Probable → **High**.
2. If Darkness is **Too light** → **None**, limiting factor = Light. Stop.
3. If Clouds is **Overcast** → **None**, limiting factor = Clouds. Stop.
4. If Darkness is **Twilight** → lower by one level (minimum None).
5. If Clouds is **Partly** → lower by one level (minimum None).
6. Clouds **Unknown** does not change the level; the result carries "cloud cover not included".
7. Limiting factor (when not set in steps 2–3):
   - the factor that lowered the level in steps 4–5 (if both, Clouds);
   - otherwise Activity, unless the level is High, in which case there is no limiting factor.

Levels in order: None < Low < Moderate < High.

## Reason text (shown with the level)

| Limiting factor | Reason key | English example |
|---|---|---|
| Light | `reason.tooLight` | "Too light" |
| Clouds (overcast) | `reason.overcast` | "Overcast" |
| Clouds (partly) | `reason.partlyCloudy` | "Partly cloudy" |
| Twilight | `reason.twilight` | "Twilight" |
| Activity | `reason.lowActivity` / `reason.someActivity` | "Low activity" / "Some activity" |
| none | `reason.goodConditions` | "Good conditions" |

Displayed as "<Level> – <reason>", e.g. "Low – overcast". All keys exist in fi, sv and en.

## Reference cases (must pass)

| # | Activity | Darkness | Clouds | Level | Limiting |
|---|---|---|---|---|---|
| 1 | Probable | Dark | Clear | High | none |
| 2 | Probable | Too light | Clear | None | Light |
| 3 | Probable | Dark | Overcast | None | Clouds |
| 4 | Probable | Twilight | Clear | Moderate | Twilight |
| 5 | Probable | Dark | Partly | Moderate | Clouds |
| 6 | Probable | Twilight | Partly | Low | Clouds |
| 7 | Possible | Dark | Clear | Moderate | Activity |
| 8 | Possible | Twilight | Partly | None | Clouds |
| 9 | Unlikely | Dark | Clear | Low | Activity |
| 10 | Unlikely | Twilight | Clear | None | Twilight |
| 11 | Probable | Dark | Unknown | High | none (cloud cover not included) |
| 12 | Unlikely | Too light | Overcast | None | Light |
