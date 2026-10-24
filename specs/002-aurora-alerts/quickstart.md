# Quickstart: Validating Aurora Alerts

Scenarios that prove the feature works end to end. Contracts are in [contracts/](contracts/);
nothing here repeats them.

## Prerequisites

- Xcode with the Swift 6.4 toolchain; Docker for Linux builds.
- An APNs key (`.p8`) with key ID and team ID, from the Apple Developer account.
- A physical iPhone (the simulator can receive pushes only via `simctl push`, which bypasses APNs).
- For deployment: SSH to the UpCloud server, DNS for the alerts subdomain, a Healthchecks.io check
  (period 5 min, grace 25 min).

## 1. Core, on macOS and Linux

```sh
swift test --package-path Packages/AuroraCore
tools/check-core-portability.sh
docker run --rm -v "$PWD":/src -w /src/Packages/AuroraCore swift:6.4.1-noble swift test
```

Expected: all tests pass on both, including every case in
[alert-rules.md](contracts/alert-rules.md) and the 001 chance-rule cases.

## 2. Service, locally

```sh
swift test --package-path Server
docker build -f Server/Dockerfile -t revontulet-alerts .
docker run --rm -p 8080:8080 \
  -e APNS_ENVIRONMENT=sandbox -e APNS_KEY_ID=… -e APNS_TEAM_ID=… -e APNS_KEY_PATH=/run/secrets/apns_key \
  -v "$PWD/AuthKey.pem":/run/secrets/apns_key:ro -v /tmp/alerts:/data revontulet-alerts
```

This is a development instance (sandbox), the one Debug builds use. Then, with a token from a Debug build on a device:

| Step | Command / action | Expected |
|---|---|---|
| Register | `curl -i -X PUT localhost:8080/v1/registration -d '{"token":"<hex>","zone":"OUJ","threshold":"moderate"}'` | `204` |
| Bad zone | same with `"zone":"XXX"` | `400 {"error":"invalidZone"}` |
| Test | `curl -i -X POST localhost:8080/v1/registration/test -d '{"token":"<hex>"}'` | `202`, "Test alert" on the phone within a minute |
| Test ×4 | repeat 3 more times | 4th gives `429` with `Retry-After` |
| Stored data | `sqlite3 /tmp/alerts/alerts.db .dump` | Only `token, zone, threshold, confirmed_at` (day-rounded) and zone state (SC-006) |
| Logs | `docker logs` | No tokens, addresses or bodies |
| Delete | `POST /v1/registration/delete` | `204`; row gone (SC-005) |

**Replay check**: start the service with `ALERTS_REPLAY=<fixture dir>` (recorded FMI responses
from a strong night, served by a stub HTTP client) and a sandbox registration for that zone:
exactly the alerts listed for that night in the fixture's expectations arrive, none in daylight.

## 3. App on a device (Debug build against the development instance from §2)

1. Fresh install → main screen → bell button → **Off, first time**: explanation, privacy link.
2. Turn on with Moderate → iOS permission prompt → allow → **On**, zone shown, "Confirmed today".
   Time it from opening the settings: under 30 seconds including reading the explanation
   (SC-004).
3. Send test → test notification arrives, title and body in the device language. Change the
   device language to Finnish, then Swedish, and send a test each time: text follows the language
   (checks R6 on a real bundle).
4. Choose a municipality in another zone (e.g. Utsjoki) → settings show the new zone; the service
   row has the new zone and no other row exists for the token.
5. Airplane mode, change threshold → "Waiting to confirm"; no error dialog anywhere. Back online
   and foreground → "Confirmed".
6. Turn off notifications for Revontulet in iOS Settings → reopen app → alerts shown off with
   "Notifications are off"; the service row is gone (R7).
7. Turn off alerts (after re-enabling) → row gone within a minute.
8. Stop the service → main screen, widgets and map behave exactly as before; only the alert
   settings show "Waiting to confirm" after a change (SC-007).

## 4. Deployment on the server

```sh
cat /opt/edge/sites/revontulet-alerts.caddy   # reverse_proxy only, no "import access_log"
docker compose -f /opt/revontulet-alerts/compose.yaml up -d
docker exec subscription-tracker-caddy-1 caddy reload --config /etc/caddy/Caddyfile
curl -s https://alerts.<domain>/v1/health    # {"status":"ok"}
docker stats --no-stream revontulet-alerts   # memory well under 150 MiB
```

Stop the container for 35 minutes → Healthchecks.io email arrives (SC-008). Start it → the first
cycle sends nothing stale (FR-009).

## 5. Release checks

- `docs/privacy.md` updated: alerts, stored data, UpCloud in Finland, 180-day retention, backup
  window (FR-019).
- Privacy label decision recorded in the spec's Privacy Review (FR-020, R11).
- Production instance verified with a TestFlight build and a test notification.
