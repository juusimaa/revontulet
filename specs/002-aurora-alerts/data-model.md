# Data Model: Aurora Alerts

Entities from [spec.md](spec.md), with where each lives. Types in **AuroraCore** are portable and
shared by the app and the alert service (Principle III). Existing types (`Station`, `Place`,
`Chance`, `ChanceLevel`, `ChanceReason`, `StationReading`, `CloudCover`) are described in
[001 data-model.md](../001-aurora-main-screen/data-model.md) and are reused unchanged.

## AuroraCore (shared)

### AlertZone

A coarse area of Finland: the area where one magnetometer station is the nearest of the 10 the
app uses. There is no separate zone table; a zone is identified by its station.

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | The station code, e.g. `OUJ`. Valid values are exactly the codes in the bundled `stations.json`. |
| `station` | `Station` | Name (shown in alerts and settings, not translated) and position. |
| `representativePosition` | `Coordinate` | The station's position; used for darkness and cloud cover (research R2). |

**Zone names**: a zone is named after its station as FMI publishes it. Southern Finland's
nearest station is Tartu (TAR) in Estonia, so alerts there say "near Tartu"; the main screen
already shows Tartu as the station for that area, so alerts and the app stay consistent. A
friendlier display name per zone is a possible later improvement.

**Zone of a place**: the station nearest to the place's coordinate by straight-line distance,
**regardless of whether it currently has data**, so the zone depends only on geography. A
previous zone is kept until another station is at least 5 km closer (same hysteresis as
`StationSelector`), so the registration is not updated back and forth at a zone border.

### AlertThreshold

`moderate` (alert on Moderate and High) or `high` (alert on High only). Default `high` (FR-003).
Raw values `"moderate"`, `"high"` are part of the HTTP contract.

### ZoneCondition

A zone's current chance to see, computed with the app's own rules at the representative position.

| Field | Type | Notes |
|---|---|---|
| `zoneID` | `String` | |
| `chance` | `Chance` | Level, limiting factor, whether clouds are included. |
| `reason` | `ChanceReason` | From `ChanceCalculator.reason`. |
| `activityStationID` | `String` | Usually the zone's own station; the next nearest with data during an outage. |
| `dataTime` | `Date` | `measuredAt` of the activity reading; used for the late-alert rule (FR-009). |

Zones whose activity cannot be computed (no station has a valid R) have no condition for that
cycle; no alert is sent for them.

### ZoneAlertState

Per zone, kept by the alert service between cycles. Not per device (spec amendment, see plan).

| Field | Type | Notes |
|---|---|---|
| `zoneID` | `String` | |
| `alertedLevels` | `Set<ChanceLevel>` | Levels (Moderate, High) alerted and not yet re-armed. |
| `belowSince` | `[ChanceLevel: Date]` | When the chance first dropped below each alerted level; re-armed after 60 min continuously below. |
| `night` | `String` | Night key, the local date (Europe/Helsinki) of the evening the night belongs to: times before 12:00 count as the previous date. |
| `alertsTonight` | `Int` | Alerts sent for this zone in `night`; reset when the night key changes; max 3. |

**State transitions** (one evaluation cycle, per level L in {Moderate, High}, see
[contracts/alert-rules.md](contracts/alert-rules.md)):

```text
            chance ≥ L, armed, < 3 tonight, data fresh
  armed ───────────────────────────────────────────▶ alerted(L)   → send alert for L
    ▲                                                    │
    │  chance < L continuously ≥ 60 min                  │ chance < L: belowSince = now
    └────────────────────────────────────────────────────┘ chance ≥ L again: belowSince cleared
```

### AlertDecision

Output of the pure rule function: `(zoneID, level, condition)` for each alert to send this cycle.
The alert service turns a decision for level L into pushes to the zone's registrations whose
threshold admits L: a Moderate alert goes to `moderate` registrations only; a High alert goes to
both `moderate` and `high` registrations.

### Registration request types (HTTP contract)

`RegistrationUpsert { token, zone, threshold }`, `RegistrationToken { token }`. Codable, shared by the app's client and the service, so both sides use one
definition ([contracts/alert-api.md](contracts/alert-api.md)).

| Field | Validation |
|---|---|
| `token` | Lowercase hex, even length, 32–200 bytes when decoded. |
| `zone` | One of the station codes. |
| `threshold` | `moderate` or `high`. |

### AlertSyncState (device side, in the core)

What the device wants versus what the service has confirmed; drives retries (FR-005, FR-006).

| Field | Type | Notes |
|---|---|---|
| `desired` | `enabled(zone, threshold)` or `disabled` | What the user set. |
| `confirmed` | same, or `nil` | Last state the service acknowledged. |
| `confirmedAt` | `Date?` | For the once-a-day re-confirmation (FR-014). |
| `token` | `String?` | Latest APNs token; a changed token is a new registration and the old one is deleted. |

`isPending = desired != confirmed || token changed`. The settings show "not yet confirmed" while
pending; alerts are shown as off as soon as `desired == disabled` (FR-006).

## Alert service (server)

### registrations (SQLite)

| Column | Type | Notes |
|---|---|---|
| `token` | `TEXT PRIMARY KEY` | APNs device token, hex. |
| `zone` | `TEXT NOT NULL` | Station code. Indexed. |
| `threshold` | `TEXT NOT NULL` | `moderate` / `high`. |
| `confirmed_at` | `INTEGER NOT NULL` | Unix seconds, day precision is enough; rounded down to the day so the column cannot reveal when the app was opened. |

Nothing else is stored: no IP address, user agent, language, history of zones or delivery log
(FR-013). Deleted when: the app deletes it; APNs answers 410 Unregistered, 400 BadDeviceToken or
400 DeviceTokenNotForTopic; or `confirmed_at` is older than 180 days (daily sweep, FR-014).

### zone_alert_state (SQLite)

One row per zone, the `ZoneAlertState` above serialised. Persisted so a restart does not re-send
alerts already sent tonight. Contains nothing about users.

### In memory only

- Test-notification counters per token (3 per hour, FR-012), cleared on restart.
- Rate-limit counters per client address (FR-017), never written to disk or logs.
- Last FMI responses (magnetometer 5 min, clouds 10 min), as in `AuroraService`.

## App (iOS, device only)

| Item | Storage | Notes |
|---|---|---|
| `AlertSyncState` | UserDefaults | Desired/confirmed state and token. |
| Zone | derived | From the current `Place` each time the main screen resolves it (FR-004). |
| Notification permission | iOS | Read on each foreground; if revoked while alerts are on, the app deletes the registration and shows alerts off (spec amendment, see plan). |
