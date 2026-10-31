# Contract: Chance-to-See Rules, v2 (moon)

Replaces [spec 001's chance rules](../../001-aurora-main-screen/contracts/chance-rules.md) (FR-003).
Every caller of `ChanceCalculator` uses this version: the main screen, the alert service's
`ZoneEvaluator` and, through [outlook-rules.md](outlook-rules.md), each night's outlook. Tests in
the core package cover every reference case (SC-001). Changes from v1 are marked **new**.

## Inputs

| Input | Values | Source |
|---|---|---|
| Activity | Unlikely, Possible, Probable | Station R vs. thresholds (spec 001), or the Kp mapping for an outlook |
| Darkness | Too light, Twilight, Dark | Sun elevation (spec 001, R6) |
| **Moon** | **Bright, Not bright** | Moon altitude and illuminated fraction ([research.md R4](../research.md)) |
| Clouds | Clear (0–3 octas), Partly (4–6), Overcast (7–8), Unknown | Nearest weather station, or the zone's cloud forecast for an outlook |

**Bright moon**: the moon's centre is above the horizon (topocentric altitude > 0°, without
refraction) **and** its illuminated fraction is at least 0.5 (FR-002).

## Rule

1. Starting level from activity: Unlikely → **Low**, Possible → **Moderate**, Probable → **High**.
2. If Darkness is **Too light** → **None**, limiting factor = Light. Stop.
3. If Clouds is **Overcast** → **None**, limiting factor = Clouds. Stop.
4. **Sky brightness (new)**: if Darkness is **Twilight** or Moon is **Bright**, lower by one
   level (minimum None). Never by two for both. Limiting factor = Twilight if Darkness is
   Twilight, otherwise **Moon**.
5. If Clouds is **Partly** → lower by one level (minimum None), limiting factor = Clouds.
6. Clouds **Unknown** does not change the level; the result carries "cloud cover not included".
7. **New:** if Activity is **Unlikely** and the level is now **None**, the limiting factor is
   **Activity**. Unlikely activity allows Low at best, so step 4 or 5 lowering it to None
   does not mean the sky or clouds hide aurora. "None – bright moon" would suggest they do.
   The details still mark the moon, twilight or clouds as limiting.
8. Limiting factor when not set in steps 2–7: Activity, unless the level is High, in which case
   there is none.

Twilight is reported over the moon when both apply, because the sun alone already explains the
step and it ends sooner on most nights.

## Reason text

| Limiting factor | Reason key | English example |
|---|---|---|
| Light | `reason.tooLight` | "Too light" |
| Clouds (overcast) | `reason.overcast` | "Overcast" |
| Clouds (partly) | `reason.partlyCloudy` | "Partly cloudy" |
| Twilight | `reason.twilight` | "Twilight" |
| **Moon** | **`reason.brightMoon`** | **"Bright moon"** |
| Activity | `reason.lowActivity` / `reason.someActivity` | "Low activity" / "Some activity" |
| none | `reason.goodConditions` | "Good conditions" |

## Alert keys (new)

Under v2, Moderate can also be reached with Probable activity, a dark sky and a bright moon. The
alert service then sends these keys ([push contract of spec 002](../../002-aurora-alerts/contracts/push-notification.md)):

| Level | Reason | Clouds | `loc-key` | English text (`%@` = station) |
|---|---|---|---|---|
| Moderate | brightMoon | known | `alert.body.brightMoon` | Strong activity near %@, but the moon is bright. |
| Moderate | brightMoon | unknown | `alert.body.brightMoon.cloudsUnknown` | Strong activity near %@ under a bright moon. Cloud cover is unknown. |

They are added to `AlertMessage.bodyKeys` and exist in fi, sv and en from 3.0. 2.0 does not
have them, so the service sends them only when `ALERT_MOON_KEYS` is on; until then it sends
`alert.body.twilight` (or `alert.body.twilight.cloudsUnknown`) for these cases. See
[research.md R9](../research.md).

## Reference cases (must pass)

Cases 1–12 of v1 hold with Moon = Not bright, except case 10 (Unlikely, Twilight, Clear), whose
limiting factor is now Activity (step 7). New cases:

| # | Activity | Darkness | Moon | Clouds | Level | Limiting |
|---|---|---|---|---|---|---|
| 13 | Probable | Dark | Bright | Clear | Moderate | Moon |
| 14 | Possible | Dark | Bright | Clear | Low | Moon |
| 15 | Unlikely | Dark | Bright | Clear | None | Activity (step 7) |
| 16 | Probable | Twilight | Bright | Clear | Moderate | Twilight |
| 17 | Probable | Dark | Bright | Partly | Low | Clouds |
| 18 | Probable | Twilight | Bright | Partly | Low | Clouds |
| 19 | Probable | Too light | Bright | Clear | None | Light |
| 20 | Probable | Dark | Bright | Overcast | None | Clouds |
| 21 | Probable | Dark | Bright | Unknown | Moderate | Moon (cloud cover not included) |
| 22 | Possible | Twilight | Bright | Clear | Low | Twilight |
| 23 | Unlikely | Dark | Not bright | Partly | None | Activity (step 7) |
| 24 | Unlikely | Twilight | Bright | Partly | None | Activity (step 7) |
