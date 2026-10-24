# Contract: Alert Service HTTP API (v1)

The only interface between the app and the alert service. Base URL
`https://alerts.<domain>/v1` for the production instance (domain chosen in T008a). The app reads
the base URL from the `AlertsBaseURL` Info.plist key, set from the `ALERTS_BASE_URL` build
setting: Release builds use the production instance, Debug builds a development instance whose
APNs environment is sandbox (research R5). HTTPS only, terminated by the existing reverse proxy
(a local development instance may use plain HTTP on localhost). JSON bodies, UTF-8.

The request and response types are defined once in `AuroraCore` (`RegistrationUpsert`,
`RegistrationToken`, `AlertAPIError`) and used by both the app and the service.

## Design rules

- **Tokens never appear in URLs**, only in request bodies, so no URL log anywhere can contain one.
- **No request logging** in the service, and the reverse proxy's site block for this host has no
  access log (FR-013). Errors are logged without request bodies or client addresses.
- **No accounts, no API keys.** Knowing a token is what authorises changing its registration; a
  token is only known to the device and to APNs.
- **Idempotent**: every call can be retried safely; the app's retry logic relies on this.
- Validation as in [data-model.md](../data-model.md#registration-request-types-http-contract).

## Endpoints

### `PUT /v1/registration`

Create or update the registration for a token (turn on, change threshold, zone change, daily
re-confirmation).

```json
{ "token": "a1b2…", "zone": "OUJ", "threshold": "high" }
```

| Status | Meaning |
|---|---|
| `204` | Stored. `confirmed_at` set to today. |
| `400` | Invalid body; response `{ "error": "invalidToken" \| "invalidZone" \| "invalidThreshold" \| "invalidBody" }`. The app does not retry 400. |
| `429` | Rate limited; `Retry-After` header in seconds. |
| `5xx` / no response | The app retries (see Retry policy). |

### `POST /v1/registration/delete`

Delete the registration for a token (turn off, token changed, notification permission revoked).

```json
{ "token": "a1b2…" }
```

`204` whether or not a registration existed (idempotent). Errors as above.

### `POST /v1/registration/test`

Send a test notification to this token (FR-012). The registration must exist.

```json
{ "token": "a1b2…" }
```

| Status | Meaning |
|---|---|
| `202` | Test notification handed to APNs. |
| `404` | No registration for this token: the app re-registers, then the user may try again. |
| `429` | More than 3 test notifications in the past hour for this token; `Retry-After` seconds, shown to the user as a time (US3 scenario 2). |

### `GET /v1/health`

`200 {"status":"ok"}` when the last evaluation cycle succeeded within 15 minutes, otherwise `503`.
Used by the container health check; contains nothing about users. The external heartbeat
(research R9) is a ping *from* the service, not a call to this endpoint.

## Rate limits (FR-017)

Per client address, in memory only, never logged: 30 requests per 10 minutes across all
endpoints. Test notifications additionally 3 per hour per token. The client address is taken
from the proxy's `X-Forwarded-For`, and only the proxy may reach the service (it is not exposed
outside the shared Docker network).

## Retry policy (app)

- Changes are retried on every app foreground and, while the app is open, with backoff
  30 s → 2 min → 10 min. No error dialogs; the settings show "not yet confirmed" (FR-005).
- `400` is not retried; the app logs it in debug builds and keeps the change pending until the
  next app version.
- `429` waits for `Retry-After`.
- Re-confirmation (`PUT` with unchanged values) happens at most once a day, when the app is
  opened (FR-014).

## Versioning

The path carries the version. A breaking change adds `/v2` and keeps `/v1` until no supported app
version uses it.
