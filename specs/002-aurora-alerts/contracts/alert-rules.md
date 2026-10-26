# Contract: Alert Rules

The fixed rules for FR-008 and FR-009. Implemented as pure functions in `AuroraCore`
(`ZoneEvaluator`, `AlertPolicy`) and developed test-first (Principle IV); tests cover every
reference case below (SC-002, SC-003). Any change to these rules is a change to the feature and
must update the spec.

## 1. Zone condition (every cycle)

For each zone (station code `Z`, representative position `P` = station position):

1. **Activity**: `StationSelector.select(for: P, readings, previous: nil)`, the same function the
   app uses. Normally this is `Z`'s own reading; if `Z` has no valid R, the next nearest station
   with one (spec edge case "station outage"). No valid R anywhere → no condition, no alert.
2. **Darkness**: `SolarPosition.darkness(P, now)`.
3. **Clouds**: `CloudSelector.select(for: P, observations)` (nearest within 100 km, else unknown).
4. **Chance**: `ChanceCalculator.chance(activity, darkness, clouds)` and its `reason`, exactly as
   in [001 chance-rules.md](../../001-aurora-main-screen/contracts/chance-rules.md).

`dataTime` = the activity reading's `measuredAt`.

## 2. Alert decision (per zone, per cycle)

Levels that can alert: **Moderate** and **High**. Let `C` be the zone's chance level now.

1. **Night**: night key = local date in Europe/Helsinki of `now − 12 h`. If it differs from the
   state's night, reset `alertsTonight` to 0. (`alertedLevels` and `belowSince` are not reset.)
2. **Re-arm**: for each alerted level L with `C < L`: if `belowSince[L]` is unset, set it to `now`;
   if `now − belowSince[L] ≥ 60 min`, remove L from `alertedLevels` and clear `belowSince[L]`.
   For each alerted level L with `C ≥ L`: clear `belowSince[L]`.
3. **Candidate**: the highest level L ∈ {Moderate, High} with `C ≥ L` and L not in
   `alertedLevels`. None → no alert.
4. **Late data**: if `now − dataTime > 20 min` → drop the candidate, do not mark it alerted
   (FR-009). It may alert later with fresh data.
5. **Nightly cap**: if `alertsTonight ≥ 3` → drop the candidate, but mark it (and every lower
   level) alerted so it does not fire the moment the night key changes.
6. **Alert**: emit `AlertDecision(zone, L, condition)`; add L **and every lower alertable level**
   to `alertedLevels` (a jump straight to High sends one High alert, not Moderate then High);
   `alertsTonight += 1`.

Recipients of a decision: Moderate → registrations with threshold `moderate`; High → registrations
with threshold `moderate` or `high`.

A registration therefore receives at most 3 alerts per night from its zone (SC-003). A device
that changes zone during a night can receive alerts from both zones; accepted, see plan.

## 3. Delivery

- Alerts are sent with normal priority (`apns-priority: 10`, no `interruption-level`, which means
  `active`), FR-011.
- `apns-expiration` = `dataTime + 20 min`, so APNs also drops an alert that cannot be delivered in
  time (FR-009), and `apns-collapse-id` = `zone-level-night`, so a retried send never shows twice.
- Pushes are sent only for decisions from the current cycle. After downtime nothing is replayed;
  the first cycle after a restart only evaluates fresh data.

## Reference cases (must pass)

All in zone OUJ, threshold irrelevant unless stated; times are Europe/Helsinki; "fresh" means
`dataTime` ≤ 5 min old. State before is `alertedLevels = {}`, `alertsTonight = 0` unless stated.

| # | Situation | Expected |
|---|---|---|
| 1 | 22:00, C = Moderate, fresh | Alert Moderate; alerted = {Moderate} |
| 2 | after 1, 22:05, C = Moderate | No alert |
| 3 | after 1, 22:10, C = High | Alert High; alerted = {Moderate, High} |
| 4 | 22:00, C = High, fresh, nothing alerted | One alert High (not Moderate too); alerted = {Moderate, High} |
| 5 | after 4, C = Moderate from 22:30 to 23:45 | High re-armed at 23:30; no alert while Moderate (Moderate still alerted) |
| 6 | after 5, 23:50, C = High | Alert High |
| 7 | after 4, C drops to Low 22:30–23:00, back to High 23:00 | No alert (below for only 30 min) |
| 8 | 22:00, C = High, `dataTime` 25 min old | No alert; nothing marked alerted |
| 9 | after 8, 22:05, C = High, fresh | Alert High |
| 10 | alertsTonight = 3, C = High (re-armed), fresh | No alert; High marked alerted |
| 11 | alertsTonight = 3 at 03:00, next alert-worthy High at 21:00 next day after re-arm | Alert (night key changed at 12:00) |
| 12 | 13:00 June, Probable activity, too light | C = None; no alert |
| 13 | 23:00, Probable, dark, overcast | C = None; no alert |
| 14 | OUJ has no valid R, nearest valid station has Probable, dark, clear | Condition uses that station; alert High |
| 15 | No station has a valid R | No condition; no alert; state unchanged |
| 16 | 22:00, Possible, dark, clouds unknown | C = Moderate (clouds not included); alert Moderate with reason "some activity, cloud cover unknown" |
