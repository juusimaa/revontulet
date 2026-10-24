# Contract: Push Notification

What the alert service sends to APNs, and how the app turns it into text. The service never knows
the device language (FR-010): the payload carries localisation keys, and iOS looks them up in the
app's `Localizable` strings (compiled from `Localizable.xcstrings`) in the device language.

## Request

| Header | Value |
|---|---|
| `apns-push-type` | `alert` |
| `apns-topic` | `fi.juusimaa.revontulet` |
| `apns-priority` | `10` |
| `apns-expiration` | `dataTime + 20 min` as Unix seconds (FR-009) |
| `apns-collapse-id` | `<zone>-<level>-<night>`, e.g. `OUJ-high-2026-11-03` |

Endpoint by the registration's `environment`: `production` → `api.push.apple.com`, `sandbox` →
`api.sandbox.push.apple.com`. TestFlight and App Store builds are production; only builds run
from Xcode are sandbox.

## Payload

```json
{
  "aps": {
    "alert": {
      "title-loc-key": "alert.title.high",
      "loc-key": "alert.body.goodConditions",
      "loc-args": ["Oulujärvi"]
    },
    "sound": "default",
    "thread-id": "aurora-alerts"
  }
}
```

No `interruption-level` (defaults to `active`, FR-011), no badge, no custom data. Nothing in the
payload identifies the user; the station name is the only argument.

## Keys

`AlertMessage.make` chooses the keys from the decision's level and the condition's reason and
`cloudsIncluded`. Under the chance rules only these combinations can reach Moderate or High:

| Level | Reason | Clouds | `loc-key` | English text (`%@` = station) |
|---|---|---|---|---|
| High | goodConditions | known | `alert.body.goodConditions` | Good conditions near %@. Look north now. |
| High | goodConditions | unknown | `alert.body.goodConditions.cloudsUnknown` | Strong activity near %@. Cloud cover is unknown. |
| Moderate | someActivity | known | `alert.body.someActivity` | Some activity near %@ and a clear, dark sky. |
| Moderate | someActivity | unknown | `alert.body.someActivity.cloudsUnknown` | Some activity near %@. Cloud cover is unknown. |
| Moderate | twilight | known | `alert.body.twilight` | Strong activity near %@, but the sky is not fully dark yet. |
| Moderate | twilight | unknown | `alert.body.twilight.cloudsUnknown` | Strong activity near %@ in twilight. Cloud cover is unknown. |
| Moderate | partlyCloudy | known | `alert.body.partlyCloudy` | Strong activity near %@ with some cloud. |

Titles: `alert.title.high` ("High chance of aurora"), `alert.title.moderate` ("Moderate chance of
aurora"). Test: `alert.title.test` ("Test alert"), `alert.body.test` ("Aurora alerts are working on
this iPhone."). Final wording is done with the UI work; the keys are binding.

Every key in `AlertMessage.allKeys` MUST exist in fi, sv and en in `Localizable.xcstrings`; a unit
test in the app target checks this, and the quickstart includes a device check because iOS's use
of String Catalogs for `loc-key` is not stated in Apple's documentation (research R6).

## Tapping

Opening the notification launches or foregrounds the app on the main screen, which refreshes as
usual and shows the result for the user's own place (US1 scenario 7). No deep link is needed.

## Responses from APNs

| Response | Action |
|---|---|
| `200` | Done. |
| `410 Unregistered` / `410 ExpiredToken` | Delete the registration, unless it was confirmed after the response's `timestamp`. |
| `400 BadDeviceToken` / `400 DeviceTokenNotForTopic` | Delete the registration, **unless** more than 10 such responses (or 10%) occur in one cycle; then delete nothing, stop sending this cycle and report failure to the heartbeat, because this is almost certainly a configuration error (wrong environment or topic). |
| `403 ExpiredProviderToken`, `InvalidProviderToken` | Configuration error: stop sending, report failure. |
| `429`, `5xx`, network error | Retry once within the cycle; then drop (no replay, FR-009). |
