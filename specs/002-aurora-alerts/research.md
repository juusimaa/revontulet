# Research: Aurora Alerts

Decisions behind [plan.md](plan.md). Library versions and Apple behaviour were checked on
2026-10-24 against official release pages and documentation (sources inline).

## R1. Running the shared core on Linux

**Decision**: The alert service depends on `AuroraCore` as a local package and calls it for every
calculation. `AuroraCore` is unchanged in shape; a Linux build and test job is added to CI.

**Rationale**: Verified on 2026-10-24: `swift build` and `swift test` for `Packages/AuroraCore` in
the `swift:6.2-noble` container (Swift 6.2.4, aarch64) build cleanly and all 76 tests in 16 suites
pass, including bundled-resource loading and the BsWfs parser. Principle III's portability work
in feature 001 is what makes this possible.

**Alternatives considered**: Re-implementing R and the chance rules in another language for the
server (e.g. TypeScript on a serverless platform) — rejected: two implementations would drift,
and an alert could disagree with the app.

## R2. Zones and their representative position

**Decision**: One zone per station the app uses (10). A place's zone is its nearest station by
straight-line distance, regardless of current data, with the same 5 km hysteresis as
`StationSelector`. The zone's conditions are computed at the station's position: activity via
`StationSelector` (so a station outage falls back to the next nearest, like the app), darkness
via `SolarPosition`, clouds via `CloudSelector` (nearest observation within 100 km).

**Rationale**: Uses the geography the app already has, with no new data set. Selecting by
geography rather than data keeps the zone, and therefore the registration, stable during station
outages. The station position is inside its own zone by definition.

**Alternatives considered**: Zone centroids (would need a new, derived data set; marginal
benefit for darkness within a zone); municipality-level zones (308 values — too fine for the
"coarse region" Principle II allows).

## R3. Server stack

**Decision**: A Swift package `Server/` with:

| Dependency | Version | Licence | Why |
|---|---|---|---|
| Hummingbird | 2.28.0 | Apache-2.0 | Small HTTP server on SwiftNIO; no request logging unless added. |
| APNSwift (`kylebrowning/APNSwift`) | 7.1.0 | Apache-2.0 | APNs over HTTP/2 with token (.p8/JWT) auth, works on Linux, handles JWT refresh. The repo moved from `swift-server-community`. |
| SQLiteNIO | 1.13.2 | MIT | Async SQLite with the SQLite amalgamation bundled, so no system library in the image. |
| AsyncHTTPClient | 1.36.2 | Apache-2.0 | Already pulled in by APNSwift; the service's `HTTPClient` conformance for FMI requests. |

All licences are compatible with AGPL-3.0, none collects data (Principle II), and the app target
gains no dependencies. Sources: GitHub release pages of each project.

**Rationale**: Swift lets the service reuse `AuroraCore` (R1). Hummingbird is the smallest
maintained Swift HTTP server; APNSwift is the maintained Swift APNs client. Using
AsyncHTTPClient for FMI requests avoids depending on FoundationNetworking's `URLSession` on Linux
in the server, while the core's own `URLSessionHTTPClient` stays available.

**Alternatives considered**: Vapor (larger than needed); raw SwiftNIO (more code to own);
Firebase Cloud Messaging or OneSignal (third-party SDKs and services that process user data,
excluded by Principle II); a JSON file instead of SQLite (no atomic updates, no index by zone).

## R4. Build and container image

**Decision**: Multi-stage Dockerfile: build on `swift:6.4.1-noble` with `swift build -c release
--static-swift-stdlib`, run on `ubuntu:noble` with only the binary, `swift-backtrace-static` and CA
certificates. Built by GitHub Actions for `linux/amd64` and pushed to
`ghcr.io/juusimaa/revontulet-alerts`, tagged with the commit SHA, like the server's other apps.
Never built on the server (2 GB RAM, no swap).

**Rationale**: This is the layout of the official Hummingbird template (which builds with
`--static-swift-stdlib` on noble). Swift 6.4.1 is the latest stable release (2026-10-15) and
matches the toolchain the app uses.

**Alternatives considered**: Static Linux SDK (musl, fully static, scratch image) — viable, but
needs a matching swift.org toolchain and Glibc→Musl import changes; revisit if image size matters.

**Server architecture**: confirmed x86_64 (`uname -m`, 2026-10-24), so the image is built for
`linux/amd64` only.

## R5. APNs: authentication, environments, invalid tokens

**Decision**:
- Token-based auth with one `.p8` key (converted to PEM for APNSwift), key ID and team ID from
  environment, key file as a Docker secret. APNSwift refreshes the JWT within Apple's rule
  ("no more than once every 20 minutes and no less than once every 60 minutes").
- One APNs environment per service instance, set by `APNS_ENVIRONMENT` (`production` by
  default). TestFlight and App Store builds use production and register with the production
  instance on the server. Builds run from Xcode get sandbox tokens and register with a separate
  development instance (`APNS_ENVIRONMENT=sandbox`), run locally in Docker or as a second
  container when needed. Release builds use the production URL and Debug builds the development
  URL (build setting, see T037). No registration stores its environment, so the production
  database holds exactly the four fields Principle II allows.
- Delete on `410 Unregistered`/`ExpiredToken` unless the registration was confirmed after the
  response's timestamp, and on `400 BadDeviceToken`/`DeviceTokenNotForTopic`, but with a circuit
  breaker: more than 10 (or 10%) such responses in one cycle are treated as a configuration error,
  so nothing is deleted and the heartbeat reports failure
  ([push-notification.md](contracts/push-notification.md)).

**Rationale**: Apple lists these as non-retryable; both 400 reasons can also be caused by the
sender's own misconfiguration, so mass deletion must not follow from one mistake.
Sources: developer.apple.com — "Establishing a token-based connection to APNs", "Sending
notification requests to APNs", "Handling notification responses from APNs".

**Alternatives considered**: Certificate-based auth (yearly renewal, one certificate per
environment); storing each token's environment in one shared instance (a fifth stored field that
Principle II does not list, and development registrations mixed into production data).

## R6. Notification text in the user's language

**Decision**: Payload uses `title-loc-key`, `loc-key` and `loc-args` (station name). Keys live in
the app's default `Localizable` table (`Localizable.xcstrings`) with `%@` placeholders. One key
per reachable (level, reason, clouds known) combination: 7 bodies, 2 titles, plus test strings.

**Rationale**: The service never learns the language (FR-010), and a language change on the
device applies to the next alert. Apple documents lookup in "`Localizable.strings`"; Xcode
compiles String Catalogs to `.strings` in the bundle and this works in practice (Apple developer
forums, thread 731626), but it is not stated in Apple's documentation, so the quickstart includes
an on-device check of all three languages.

**Alternatives considered**: Sending the language with the registration (more data, violates
FR-010); a Notification Service Extension that composes the text on the device (extra target and
memory limits for no gain over localisation keys).

## R7. Notification permission revoked in iOS Settings

**Decision**: On every foreground, the app reads the notification authorisation. If alerts are
on and notifications are no longer allowed, the app deletes the registration and shows alerts as
off with "Notifications are off for Revontulet" and an Open Settings action.

**Rationale**: APNs does not report a disabled app: it keeps answering 200, and iOS silently
drops the notification (Apple developer forums). Without this, the service would keep a zone for
a device that cannot receive alerts. Deleting is the privacy-preserving default; turning
notifications back on does not turn alerts back on silently.

**Spec impact**: the edge case "notifications revoked" is corrected (see plan, Spec amendments).

## R8. Repeat rules and nightly cap kept per zone

**Decision**: Alert state (alerted levels, re-arm timers, alerts tonight) is kept per zone, not
per registration ([alert-rules.md](contracts/alert-rules.md)). All registrations in a zone receive
the same alerts, filtered by threshold, so a per-zone cap of 3 per night caps every registration.

**Rationale**: No per-device history is stored, which keeps FR-013's data list exact.

**Trade-off accepted**: A device that changes zone during a night can receive alerts from both
zones (at most 3 from each). Rare, and the alerts are correct for where the device is.

## R9. Monitoring

**Decision**: Healthchecks.io free plan. The service pings a check URL after every successful
evaluation cycle (every 5 minutes) and pings `/fail` on configuration errors (APNs auth, circuit
breaker). Check period 5 min, grace 25 min, so an outage is reported by email within about 30
minutes (SC-008). The ping URL is a secret in the service's environment. The container also has
a Docker health check against `GET /v1/health`.

**Rationale**: Free plan (20 checks) covers this; the ping contains no user data. Source:
healthchecks.io/pricing, healthchecks.io/docs.

**Alternatives considered**: UpCloud's own monitoring (only sees the server, not whether cycles
run); self-hosted monitoring on the same server (fails together with it).

## R10. Hosting on the existing server

**Decision**: Its own Compose project at `/opt/revontulet-alerts` on the UpCloud server
(Helsinki, 1 CPU / 2 GB, ~880 MB available), joined to the external `edge` network, with
`mem_limit: 150m`, `restart: unless-stopped`, SQLite on `/var/lib/revontulet-alerts`, the APNs key
as a Docker secret. Caddy site file `/opt/edge/sites/revontulet-alerts.caddy` with
`reverse_proxy` only — **no `import access_log`**. Caddy is reloaded with `caddy reload`. The
service's port is not published on the host.

Backups: the service writes a nightly `VACUUM INTO` copy that overwrites the previous one, so a
deleted registration survives in a backup for at most about a day; the privacy policy says so. Loss
of the database is recoverable: active apps re-confirm daily when opened.

**Rationale**: Follows the pattern the server's other apps use (`bikelog.caddy`,
`gymnotebook.caddy`); measured memory headroom is ample for a ~30–100 MB process.

## R11. App Store privacy label

**Decision (confirmed by the developer on 2026-10-25, recorded in the spec's Privacy Review, FR-020)**:
Declare **Coarse Location** and **Device ID**, both for **App Functionality**, **not used for
tracking**, and **not linked to the user's identity**.

**Rationale**: Apple defines collecting as storing data off the device beyond servicing a
request in real time, so the zone kept for alerts is collected Coarse Location ("lower resolution
than … three or more decimal places"). Apple does not mention push tokens explicitly; a stored
per-device token is best declared as Device ID. The optional-disclosure exemption does not apply
(alerts are part of the app's function, and the data is not re-entered by the user each time).
"Not linked" is a judgement: there are no accounts and nothing ties the token to a person;
Apple's definition allows "not linked" when protections against linking are in place. The
conservative alternative, "Linked to You", stays open for the release decision.

Source: developer.apple.com/app-store/app-privacy-details.

## R12. Abuse protection without accounts

**Decision**: Strict validation of every field, tokens only in bodies, in-memory rate limits per
client address (30 requests / 10 min) and per token for tests (3 / hour), and the service
reachable only through the proxy. Fake tokens are removed by the first APNs response.

**Rationale**: Enough for a free, low-traffic service; nothing to gain from accounts, which
Principle II forbids.

**Alternatives considered**: App Attest (proves requests come from the genuine app, but adds a
key exchange and Apple calls for each registration) — deferred unless abuse appears.

## R13. App behaviour without background work

**Decision**: The app does no background refresh for alerts. Registration sync runs on
foreground and while the app is open; the zone is updated when the main screen resolves a place
in a new zone. The APNs token is requested on each launch while alerts are on, as Apple
recommends, and a changed token replaces the old registration.

**Rationale**: Alerts are pushed, so the app does not need to run in the background; this keeps
Principle V's energy rules trivially satisfied and avoids background location entirely
(FR-004).
