---

description: "Task list for the Aurora Alerts feature"
---

# Tasks: Aurora Alerts

**Input**: Design documents from `specs/002-aurora-alerts/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Included. Constitution v1.1.0 Principle IV requires test-first development for domain
logic wherever it runs, including alert decisions in the service: write each test task first and
see it fail before the matching implementation task. Service shells are tested with fakes; UI
flows with UI tests.

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on
its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story the task belongs to (US1, US2, US3)

## Path Conventions

- Core package: `Packages/AuroraCore/Sources/AuroraCore/Alerts/`, tests in
  `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/`
- Alert service: `Server/Sources/AlertServer/` (library), `Server/Sources/alert-service/`
  (executable), tests in `Server/Tests/AlertServerTests/`
- iOS app: `Revontulet/`, unit tests in `RevontuletTests/`, UI tests in `RevontuletUITests/`
- Rules for all core code: no imports of SwiftUI, UIKit, CoreLocation, Combine, os/OSLog or
  `XMLParser`; `#if canImport(FoundationNetworking)` for URLSession; all public types `Sendable`;
  must build and test on macOS and Linux (`tools/check-core-portability.sh`, CI Linux job).
- Rules for the service: never log request bodies, tokens or client addresses; no request-logging
  middleware (FR-013, contracts/alert-api.md).
- All UI work (views, layout, visual polish) MUST use the `ios-ui-craft` skill (Principle VI).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Package skeletons, build configuration, CI and deployment files

- [X] T001 Create the service package `Server/Package.swift`: swift-tools-version 6.2, Swift 6 language mode, platforms macOS 26; dependencies `hummingbird` from 2.28.0 (github.com/hummingbird-project/hummingbird), `APNSwift` from 7.1.0 (github.com/kylebrowning/APNSwift — the repo moved from swift-server-community), `sqlite-nio` from 1.13.2 (github.com/vapor/sqlite-nio), `async-http-client` from 1.36.2, and `AuroraCore` by path `../Packages/AuroraCore`; targets `AlertServer` (library), `alert-service` (executable, depends on AlertServer), `AlertServerTests`; add placeholder sources so `swift build --package-path Server` succeeds
- [X] T002 [P] Create `Packages/AuroraCore/Sources/AuroraCore/Alerts/` and `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/` (with a placeholder test so the folder is part of the target) and `Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/alerts/`
- [ ] T003 [P] Add a `RevontuletTests` unit test target (bundle.unit-test, iOS, host app Revontulet, bundle id `fi.juusimaa.revontulet.tests`) to `project.yml` and add it to the Revontulet scheme's test targets; create `RevontuletTests/PlaceholderTests.swift`; regenerate with `xcodegen generate`
- [ ] T004 [P] Enable push in `project.yml`: create `Revontulet/Revontulet.entitlements` with `aps-environment` = `development` (automatic signing switches it to production for TestFlight/App Store exports), set `CODE_SIGN_ENTITLEMENTS` for the Revontulet target; regenerate with `xcodegen generate`
- [ ] T005 [P] Create `Server/Dockerfile` (research R4): build stage `swift:6.4.1-noble`, copy `Packages/AuroraCore` and `Server`, `swift build -c release --static-swift-stdlib --package-path Server`; run stage `ubuntu:noble` with `ca-certificates`, the `alert-service` binary and `swift-backtrace-static`; non-root user; `EXPOSE 8080`; `HEALTHCHECK` calling `GET /v1/health`; build context is the repository root; add `.dockerignore` at the repository root (the build context) excluding `.build`, `build`, `Revontulet*`
- [ ] T006 [P] Create `.github/workflows/alert-service.yml`: on pull requests and on pushes to any branch (including feature branches such as `002-aurora-alerts`) touching `Packages/AuroraCore/**` or `Server/**`, run `swift test` for `Packages/AuroraCore` and `Server` in the `swift:6.4.1-noble` container; on pushes to `main`, build `Server/Dockerfile` for `linux/amd64` only (server is x86_64) and push `ghcr.io/juusimaa/revontulet-alerts:sha-<short sha>` and `:main` using `GITHUB_TOKEN`
- [ ] T007 [P] Create deployment files (research R10): `Server/deploy/compose.yaml` (service `revontulet-alerts`, image `ghcr.io/juusimaa/revontulet-alerts:<tag>`, `restart: unless-stopped`, `mem_limit: 150m`, volume `/var/lib/revontulet-alerts:/data`, secret `apns_key` from `/opt/revontulet-alerts/AuthKey.pem`, `env_file: /opt/revontulet-alerts/alerts.env`, external network `edge`, no published ports) and `Server/deploy/revontulet-alerts.caddy` (`alerts.<domain> { reverse_proxy revontulet-alerts:8080 }` with a comment that `import access_log` must never be added); and `Server/deploy/alerts.env.example` listing `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`, `APNS_TOPIC=fi.juusimaa.revontulet`, `HEALTHCHECK_PING_URL`, `DATABASE_PATH=/data/alerts.db`, `APNS_ENVIRONMENT=production`
- [ ] T007a Choose the production subdomain `alerts.<domain>` and create its DNS A record pointing at the UpCloud server; write the domain into `Server/deploy/revontulet-alerts.caddy` (T007) and the Release `ALERTS_BASE_URL` (T037)
- [ ] T007b Push `002-aurora-alerts` and open a draft pull request to `main` so every later push shows the T006 status checks on the PR; push after each logical group of commits, not after every commit

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared types used by the app, the service and every story

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests (write first, must fail)

- [ ] T008 [P] Write zone tests in `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertZonesTests.swift`: `AlertZones.all()` returns exactly one zone per bundled station (10) with `id` = station code; `zone(for:previous:in:)` returns the nearest station by straight-line distance regardless of data; a previous zone is kept unless another station is at least 5 km closer; positions in Utsjoki (69.91, 27.03), Oulu (65.01, 25.47) and Helsinki (60.17, 24.94) map to KEV, OUJ and TAR respectively
- [ ] T009 [P] Write HTTP contract type tests in `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertAPIModelsTests.swift`: JSON round-trip of `RegistrationUpsert` / `RegistrationToken` with the exact field names in contracts/alert-api.md; `RegistrationValidation.validate` rejects tokens that are not "Lowercase hex, even length, 32–200 bytes when decoded" (`invalidToken`), `zone` not "One of the station codes" (`invalidZone`), `threshold` other than "`moderate` or `high`" (`invalidThreshold`)

### Implementation

- [ ] T010 [P] Implement `AlertZone` and `AlertZones` in `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertZones.swift` per contracts/aurora-core-alerts-api.md (reuse `ReferenceData.loadStations()` and `Geo.distanceKm`; hysteresis constant 5 km shared with `StationSelector.hysteresisKm`) — makes T008 pass
- [ ] T011 [P] Implement `AlertThreshold` (`moderate`, `high`; default `high`), `RegistrationUpsert` (`token`, `zone`, `threshold`), `RegistrationToken` (`token`), `AlertAPIError` (`invalidToken`, `invalidZone`, `invalidThreshold`, `invalidBody`) and `RegistrationValidation` in `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertAPIModels.swift` — makes T009 pass
- [ ] T012 Implement `RegistrationStore` in `Server/Sources/AlertServer/RegistrationStore.swift` with SQLiteNIO: create tables `registrations(token TEXT PRIMARY KEY, zone TEXT NOT NULL, threshold TEXT NOT NULL, confirmed_at INTEGER NOT NULL)` with an index on `zone`, and `zone_alert_state(zone TEXT PRIMARY KEY, state TEXT NOT NULL)`; operations upsert (sets `confirmed_at` to the start of the current UTC day in Unix seconds), delete, registrations(inZone:), deleteConfirmed(before:), load/save zone state; no other columns (FR-013); tests in `Server/Tests/AlertServerTests/RegistrationStoreTests.swift` using a temporary database file
- [ ] T013 [P] Implement configuration from environment in `Server/Sources/AlertServer/Configuration.swift` (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`, `APNS_TOPIC`, `HEALTHCHECK_PING_URL`, `DATABASE_PATH`, `APNS_ENVIRONMENT` (`production` default, or `sandbox` for a development instance), `PORT` default 8080) failing fast with a clear message when a required value is missing
- [ ] T014 Implement the HTTP application in `Server/Sources/AlertServer/Application.swift` and `Server/Sources/alert-service/main.swift`: Hummingbird router under `/v1`, JSON coding with the core types, no request-logging middleware, error responses `{"error": …}` per contracts/alert-api.md, `GET /v1/health` (200 `{"status":"ok"}` when the last evaluation cycle succeeded within 15 minutes, else 503), and a logger configured never to include bodies or addresses
- [ ] T015 [P] Implement the in-memory rate limiter in `Server/Sources/AlertServer/RateLimiter.swift`: 30 requests per 10 minutes per client address from `X-Forwarded-For` (first entry), `429` with `Retry-After` seconds; never persisted or logged; tests in `Server/Tests/AlertServerTests/RateLimiterTests.swift` with an injected clock

**Checkpoint**: Shared zone and contract types exist in the core; the service starts, stores
registrations and answers health checks.

---

## Phase 3: User Story 1 - Get told when the aurora is visible near me (Priority: P1) 🎯 MVP

**Goal**: A user turns alerts on with a threshold and receives one localized notification when
their zone's chance reaches it; tapping opens the main screen.

**Independent Test**: Turn alerts on with threshold Moderate, replay recorded FMI data in which
the zone rises from Low to Moderate on a dark, clear night, and verify one notification in the
device language naming level, zone and reason; tapping opens the main screen.

### Tests for User Story 1 (write first, must fail)

- [ ] T016 [P] [US1] Record alert fixtures with a new mode in `tools/record-fixtures.py` (`--alert-night <start> <end>`): FMI open data magnetometer for all stations and TotalCloudCover for Finland over a past night window, in 5-minute request slices as the service would fetch them, into `Packages/AuroraCore/Tests/AuroraCoreTests/Fixtures/alerts/<YYYYMMDD>/`; record at least 3 nights — one strong (FMI R red at a northern station), one moderate and one quiet — which with T017's 17+ synthetic nights make up SC-002's 20 reference nights, plus each night's FMI reference R values for hand-checking `expected.json` (list of expected `(zone, level, time)` alerts, reviewed against FMI's published R and the chance rules)
- [ ] T017 [P] [US1] Write `AlertPolicy` tests in `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertPolicyTests.swift` covering every reference case 1–16 in contracts/alert-rules.md, plus at least 17 synthetic night sequences of `ZoneCondition`s (together with T016's ≥ 3 recorded nights, SC-002's 20) (strong, moderate, flickering around a threshold, daylight, overcast, late data, cap reached) asserting alerts are sent exactly when the documented rules say and never in daylight or below threshold (SC-002), never more than 3 per zone per night (SC-003); and `admits(_:_:)`: Moderate alert → `moderate` only, High alert → `moderate` and `high`
- [ ] T018 [P] [US1] Write `ZoneEvaluator` tests in `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/ZoneEvaluatorTests.swift` with the existing `StubHTTPClient` and the T016 fixtures: one condition per zone with data; a zone whose station has no valid R uses the next nearest station with one; no valid R anywhere gives no conditions; failed cloud fetch gives unknown clouds; failed magnetometer fetch throws `AuroraServiceError.offline`; data fetched no more often than every 5 min (magnetometer) and 10 min (clouds); each condition equals what `AuroraService.refresh` returns for a `Place` at the station position with the same data (app and alert agree)
- [ ] T019 [P] [US1] Write `AlertMessage` tests in `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertMessageTests.swift`: every reachable (level, reason, clouds known) combination maps to the title and body keys in contracts/push-notification.md with the station name as the only argument; `allKeys` contains exactly the 11 keys listed there
- [ ] T020 [P] [US1] Write `AlertSync` tests (enable path) in `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertSyncTests.swift` with a fake `AlertAPI` and in-memory store: enabling sends one upsert with token, zone and threshold; a zone change sends an upsert with only the new zone; a token change upserts the new token and deletes the old one; unreachable keeps the change pending and retries on the next `sync`; re-confirmation is sent at most once per day
- [ ] T021 [P] [US1] Write service tests in `Server/Tests/AlertServerTests/RegistrationRoutesTests.swift` for `PUT /v1/registration`: 204 and stored row; 400 with each `AlertAPIError`; malformed JSON → `invalidBody`; 429 from the rate limiter
- [ ] T022 [P] [US1] Write dispatch tests in `Server/Tests/AlertServerTests/DispatcherTests.swift` with a fake `PushSender`: recipients filtered by threshold; headers `apns-push-type: alert`, `apns-priority: 10`, `apns-expiration` = dataTime + 20 min, `apns-collapse-id` = `<zone>-<level>-<night>`, no `interruption-level`; payload exactly as contracts/push-notification.md; 410 deletes unless `confirmed_at` ≥ the start of the UTC day of the response's `timestamp`; 400 BadDeviceToken/DeviceTokenNotForTopic deletes, but more than 10 (or 10%) in one cycle deletes nothing, stops the cycle and reports failure; 403 provider-token errors stop and report failure; 429/5xx retried once then dropped
- [ ] T023 [P] [US1] Write evaluation loop tests in `Server/Tests/AlertServerTests/EvaluationLoopTests.swift` with a stub `ZoneEvaluator` source, fake sender and clock: decisions are dispatched in the same cycle; zone state is persisted after each cycle; after a restart with persisted state, alerts already sent tonight are not re-sent and nothing stale is sent (FR-009); a successful cycle pings the heartbeat and a configuration failure pings `/fail`; replaying the T016 strong-night fixture produces exactly `expected.json`'s alerts

### Implementation for User Story 1

- [ ] T024 [P] [US1] Implement `ZoneCondition`, `ZoneAlertState` and `AlertDecision` in `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertModels.swift` per data-model.md (night key = "local date (Europe/Helsinki) of the evening the night belongs to: times before 12:00 count as the previous date")
- [ ] T025 [US1] Implement `AlertPolicy.decide` and `admits` in `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertPolicy.swift` exactly per contracts/alert-rules.md §2 (re-arm after 60 min continuously below, highest level only with lower levels marked, late data > 20 min dropped without marking, cap 3 per night marks without sending) — makes T017 pass
- [ ] T026 [US1] Implement `ZoneEvaluator` actor in `Packages/AuroraCore/Sources/AuroraCore/Alerts/ZoneEvaluator.swift` reusing `FMIClient`, `AuroraService.readings`, `StationSelector`, `SolarPosition`, `CloudSelector`, `ChanceCalculator` with the same due intervals as `AuroraService`; no new calculation — makes T018 pass
- [ ] T027 [P] [US1] Implement `AlertMessage` in `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertMessage.swift` — makes T019 pass
- [ ] T028 [US1] Implement `AlertAPI`, `AlertAPIFailure`, `AlertSyncState`, `AlertSyncStore` and the `AlertSync` actor (enable, threshold, zone change, token change, sync with once-a-day re-confirmation and backoff 30 s → 2 min → 10 min) in `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertSync.swift`, and `URLSessionAlertAPI` (PUT/POST JSON, maps 204/202/400/404/429/other per contracts/alert-api.md, tokens only in bodies) in `Packages/AuroraCore/Sources/AuroraCore/Alerts/URLSessionAlertAPI.swift` — makes T020 pass; run `tools/check-core-portability.sh`
- [ ] T029 [US1] Implement `PUT /v1/registration` in `Server/Sources/AlertServer/RegistrationRoutes.swift` using `RegistrationValidation` and `RegistrationStore` — makes T021 pass
- [ ] T030 [US1] Implement `PushSender` protocol and `APNSPushSender` in `Server/Sources/AlertServer/PushSender.swift` with APNSwift: JWT auth from the PEM key (`.jwt(privateKey:keyIdentifier:teamIdentifier:)`), one client for the instance's `APNS_ENVIRONMENT` (`production` → `.production`, api.push.apple.com; `sandbox` → `.development`, api.sandbox.push.apple.com), alert payload with `title-loc-key`, `loc-key`, `loc-args`, `sound: default`, `thread-id: aurora-alerts`, mapping APNs responses to a small result enum
- [ ] T031 [US1] Implement `Dispatcher` in `Server/Sources/AlertServer/Dispatcher.swift` (recipients, headers, response handling, circuit breaker) — makes T022 pass
- [ ] T032 [US1] Implement `EvaluationLoop` in `Server/Sources/AlertServer/EvaluationLoop.swift` as a service-lifecycle service: every 5 minutes call `ZoneEvaluator.evaluate`, `AlertPolicy.decide` per zone with persisted state, dispatch, save state, record last success for `/v1/health`, ping `HEALTHCHECK_PING_URL` (or `/fail`) with AsyncHTTPClient; the FMI `HTTPClient` conformance uses AsyncHTTPClient in `Server/Sources/AlertServer/AsyncHTTPClientFMI.swift` — makes T023 pass; wire it in `main.swift`
- [ ] T033 [P] [US1] Add the alert strings to `Revontulet/Resources/Localizable.xcstrings` in en, fi and sv for every key in contracts/push-notification.md, each body with one `%@` for the station name, in the default `Localizable` table
- [ ] T034 [P] [US1] Write `RevontuletTests/AlertStringsTests.swift`: for every key in `AlertMessage.allKeys`, the app bundle has a non-empty translation in en, fi and sv (look up via the `.lproj` bundles) and bodies contain exactly one `%@`
- [ ] T035 [P] [US1] Implement `PushRegistration` in `Revontulet/Platform/PushRegistration.swift`: `UIApplicationDelegateAdaptor` app delegate that calls `registerForRemoteNotifications()`, converts the token to lowercase hex and forwards it to `AlertSync.tokenChanged`; requests the token on each launch while alerts are on
- [ ] T036 [P] [US1] Implement `NotificationPermission` in `Revontulet/Platform/NotificationPermission.swift` (current status; request `.alert` and `.sound`, no badge) and `UserDefaultsAlertSyncStore` in `Revontulet/Platform/UserDefaultsAlertSyncStore.swift`
- [ ] T037 [P] [US1] Add the `ALERTS_BASE_URL` build setting in `project.yml` (Release: `https://alerts.<domain>/v1` from T007a; Debug: the development instance, default `http://localhost:8080/v1` with an App Transport Security exception for localhost in Debug only) and an `AlertsBaseURL = $(ALERTS_BASE_URL)` key in a minimal `Revontulet/Info.plist` merged via `INFOPLIST_FILE`; add `Revontulet/App/AlertConfiguration.swift` that reads `AlertsBaseURL` from `Bundle.main`; wire `AlertSync` with `URLSessionAlertAPI` in `Revontulet/App/RevontuletApp.swift`; add a `-uiTestAlertsStub` launch argument that swaps in an in-memory fake `AlertAPI` and a fake permission (granted) for UI tests
- [ ] T038 [US1] Update the zone from the main screen in `Revontulet/MainScreen/MainScreenModel.swift`: whenever a result is computed for a place in Finland, compute `AlertZones.zone(for: place.coordinate, previous:)` and call `AlertSync.zoneChanged` only when the zone differs; no extra location requests (FR-004)
- [ ] T039 [US1] Build `AlertSettingsModel` (`@Observable`, `@MainActor`) in `Revontulet/Alerts/AlertSettingsModel.swift` and `AlertSettingsView` in `Revontulet/Alerts/AlertSettingsView.swift` for the **Off**, **Asking permission**, **On** and **No zone yet** states of contracts/alert-settings-states.md (No zone yet: "Choose a place in Finland first", turning on not possible, Open place picker): threshold picker (default High), "Turn on alerts" → permission request → enable; On shows zone by station name and threshold — using the `ios-ui-craft` skill
- [ ] T040 [US1] Add the bell toolbar button to `Revontulet/MainScreen/MainScreenView.swift` that opens the alert settings, filled while alerts are on, with an accessibility label stating on or off — using the `ios-ui-craft` skill
- [ ] T041 [US1] Ensure tapping an alert opens the main screen and triggers its normal refresh (foreground handling in `Revontulet/App/RevontuletApp.swift`; no deep link)
- [ ] T042 [US1] Write UI test `RevontuletUITests/AlertSettingsUITests.swift` (with `-uiTestAlertsStub -uiTestStubs -uiTestLocation 65.01,25.47`): turn on with Moderate → On state shows the Oulu-area zone and Moderate; bell button shows the on state; with `-uiTestLocationDenied -uiTestResetCache` the settings show **No zone yet**
- [ ] T043 [US1] Deploy the production instance (quickstart §4, `APNS_ENVIRONMENT=production`): create the APNs key in the Apple Developer account and convert it with `openssl pkcs8 -nocrypt -in AuthKey.p8 -out AuthKey.pem`, create the Healthchecks.io check (period 5 min, grace 25 min), copy `Server/deploy/` files to `/opt/revontulet-alerts/` and `/opt/edge/sites/`, `docker compose up -d`, `caddy reload`, verify `/v1/health`, memory under 150 MiB and that Caddy writes no access log for the host

**Checkpoint**: With alerts turned on, a device receives correct, localized alerts for its zone.

---

## Phase 4: User Story 2 - Stay in control and private (Priority: P2)

**Goal**: The user sees what alerts send before turning them on, can change the threshold or turn
alerts off (deleting the registration), and the app copes with denied or revoked permission and
an unreachable service without error dialogs.

**Independent Test**: Turn alerts on, change the threshold, turn them off; after each step the
service stores the new values, then nothing for the device.

### Tests for User Story 2 (write first, must fail)

- [ ] T044 [P] [US2] Extend `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertSyncTests.swift`: disabling shows alerts off immediately (`desired == disabled`) and sends delete; delete is retried until confirmed; a threshold change sends one upsert; 400 is not retried; 429 waits for `Retry-After`; "permission revoked" while on deletes and disables
- [ ] T045 [P] [US2] Write `Server/Tests/AlertServerTests/DeleteAndRetentionTests.swift`: `POST /v1/registration/delete` returns 204 whether or not the row exists; registrations with `confirmed_at` older than 180 days are deleted by the daily sweep; the nightly backup overwrites the previous copy

### Implementation for User Story 2

- [ ] T046 [US2] Implement disable, delete retries and permission-revoked handling in `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertSync.swift` — makes T044 pass
- [ ] T047 [US2] Implement `POST /v1/registration/delete` in `Server/Sources/AlertServer/RegistrationRoutes.swift`, and `Maintenance` in `Server/Sources/AlertServer/Maintenance.swift`: daily retention sweep (180 days, FR-014) and nightly `VACUUM INTO '/data/alerts-backup.db'` overwriting the previous backup — makes T045 pass
- [ ] T048 [US2] Add the **Off, first time** explanation (what is sent: anonymous notification address, zone, threshold; where: the developer's alert service in Finland; that turning off deletes it; privacy policy link, FR-002), **Permission denied** (Open Settings), **On, confirming** ("Waiting to confirm", no error dialog), **Turning off** (shown off immediately, "Removing…") and threshold change while on, in `Revontulet/Alerts/AlertSettingsView.swift` and `Revontulet/Alerts/AlertSettingsModel.swift` — using the `ios-ui-craft` skill
- [ ] T049 [US2] On every foreground, check notification permission in `Revontulet/Alerts/AlertSettingsModel.swift` (or app wiring) and, if alerts are on and notifications are no longer allowed, call the permission-revoked path and show alerts off with "Notifications are off for Revontulet" (research R7)
- [ ] T050 [US2] Make sure no alert-service failure surfaces outside the alert settings: review `Revontulet/App/RevontuletApp.swift` and `Revontulet/MainScreen/` for any error path from `AlertSync` (FR-007)
- [ ] T051 [P] [US2] Extend `RevontuletUITests/AlertSettingsUITests.swift`: first-time explanation and privacy link shown; change threshold; turn off shows off immediately; with the stub API set unreachable, a change shows "Waiting to confirm" and no alert dialog appears anywhere
- [ ] T052 [P] [US2] Update `docs/privacy.md` (FR-019): an "Aurora alerts (optional)" section — off by default; what is stored (push token and whether it is a development or production build, zone by station area, threshold, day of last confirmation), why, where (UpCloud, Helsinki, Finland), retention (deleted on turn-off, on invalid token, after 180 days without confirmation; backup copy kept at most about one day), no IP addresses or language stored, no sharing; update the "network requests" and "does not collect" statements and the date

**Checkpoint**: Users can see and control exactly what alerts send, and turning off deletes it.

---

## Phase 5: User Story 3 - Know that alerts work (Priority: P3)

**Goal**: A user can send themselves a test notification and see when the service last confirmed
the registration; the settings explain when no alerts are possible for lack of darkness.

**Independent Test**: With alerts on, request a test notification; it arrives within a minute,
marked as a test; a fourth request within an hour is refused with a time to try again.

### Tests for User Story 3 (write first, must fail)

- [ ] T053 [P] [US3] Write `Server/Tests/AlertServerTests/TestNotificationTests.swift`: `POST /v1/registration/test` → 202 and one push with `alert.title.test` / `alert.body.test`; 404 when not registered; 4th request within an hour → 429 with `Retry-After`
- [ ] T054 [P] [US3] Write `Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertSeasonTests.swift`: `AlertSeason.hasDarknessWithin24h(zone:from:)` is false at KEV in late June and true in November (checked at 15-minute steps with `SolarPosition.darkness` ≠ `tooLight`); and extend `AlertSyncTests.swift` for `sendTest` mapping `notRegistered` (re-register) and `rateLimited`

### Implementation for User Story 3

- [ ] T055 [US3] Implement `POST /v1/registration/test` with a per-token limit of 3 per hour (in memory) in `Server/Sources/AlertServer/RegistrationRoutes.swift` using `AlertMessage.test` — makes T053 pass
- [ ] T056 [US3] Implement `AlertSeason` in `Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertSeason.swift` and `sendTest` in `AlertSync` — makes T054 pass
- [ ] T057 [US3] Add "Send test", "Test alert sent" / "Try again at <time>", "Confirmed <relative date>" and the **On, no dark nights** note ("Alerts resume when nights get dark again") to `Revontulet/Alerts/AlertSettingsView.swift` and `AlertSettingsModel.swift` — using the `ios-ui-craft` skill
- [ ] T058 [P] [US3] Extend `RevontuletUITests/AlertSettingsUITests.swift`: send test shows "Test alert sent"; with the stub rate-limited, shows a try-again time

**Checkpoint**: All three stories work on their own and together.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verification, documentation and release readiness

- [ ] T059 [P] Run the accessibility audit UI test on the alert settings (Dynamic Type sizes, VoiceOver labels, contrast; bell state not by symbol alone) and check every settings state in Dark Mode and with Reduce Motion and Reduce Transparency on (Principle VI) in `RevontuletUITests/AlertSettingsUITests.swift`
- [ ] T060 [P] Update `README.md`: alerts feature, the `Server/` package, how to run the service locally, and the privacy summary
- [ ] T061 [P] Record the App Store privacy label decision (Coarse Location and Device ID, App Functionality, not tracking; linked or not linked) in the Privacy Review of `specs/002-aurora-alerts/spec.md` (FR-020, research R11) — the developer makes the final call
- [ ] T062 Run every scenario in `specs/002-aurora-alerts/quickstart.md`, including the on-device check of notification text in en, fi and sv (research R6), the service-down check (SC-007) and the 35-minute heartbeat check (SC-008)
- [ ] T062a Measure alert delivery time against the production instance (SC-001): for every alert during the first strong aurora night after deployment, or for a replay of a recorded strong night with the evaluation clock set to now, compare the notification's arrival time on the device with the FMI data time it was based on; at least 95% within 15 minutes; record the result in `specs/002-aurora-alerts/quickstart.md` §5
- [ ] T063 Verify with a TestFlight build from the feature-branch Xcode Cloud workflow (started manually; `main` is not merged yet) that production push works end to end (the build registers with the production instance and a test notification arrives)
- [ ] T064 Mark the draft pull request from `002-aurora-alerts` to `main` (T007b) ready for review, with the Constitution Check (v1.1.0) confirmed in the description and `MARKETING_VERSION` bumped to `2.0` in `project.yml`; all tests pass on macOS and Linux

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T007a (domain) is needed before T037 and T043.
- **Foundational (Phase 2)**: Depends on T001–T002; blocks all stories.
- **US1 (Phase 3)**: Depends on Phase 2. Deployment (T043) needs T005–T007 and the US1 service tasks.
- **US2 (Phase 4)**: Depends on Phase 2 and on T028 (`AlertSync`) and T039 (settings view) from US1, which it extends.
- **US3 (Phase 5)**: Depends on Phase 2 and on T028, T039 and a deployed service (T043) for the device check.
- **Polish (Phase 6)**: After the stories to be shipped.

### Within Each User Story

- Tests first and failing, then implementation (Principle IV).
- Core models (T024) → policy and evaluator (T025, T026) → service dispatch and loop (T031, T032).
- Core sync (T028) → app platform adapters (T035–T037) → zone updates and UI (T038–T040).

### Parallel Opportunities

- Setup: T002–T007 in parallel after T001; T007a any time before T037; T007b after T006.
- Foundational: T008 ∥ T009, then T010 ∥ T011; T013 ∥ T015 alongside T012.
- US1: tests T016–T023 in parallel; T024 ∥ T027 ∥ T033 ∥ T034 ∥ T035 ∥ T036 ∥ T037.
- US2: T044 ∥ T045 ∥ T051 ∥ T052.
- US3: T053 ∥ T054.

---

## Parallel Example: User Story 1

```bash
# Tests first, all independent files:
Task: "AlertPolicy reference cases in Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertPolicyTests.swift"
Task: "ZoneEvaluator tests in Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/ZoneEvaluatorTests.swift"
Task: "AlertMessage tests in Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertMessageTests.swift"
Task: "Dispatcher tests in Server/Tests/AlertServerTests/DispatcherTests.swift"

# Then independent implementation files:
Task: "Alert models in Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertModels.swift"
Task: "AlertMessage in Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertMessage.swift"
Task: "Alert strings in Revontulet/Resources/Localizable.xcstrings"
Task: "PushRegistration in Revontulet/Platform/PushRegistration.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 (Setup) and Phase 2 (Foundational).
2. Phase 3 (US1), including deployment (T043).
3. **Stop and validate**: replay a strong night, then a test notification on a device: a Debug build against a local development instance, then a TestFlight build against the production instance.
4. Do not ship US1 alone to the App Store: FR-002 (explanation before opt-in), turning off with
   deletion (FR-006) and the privacy policy (FR-019) are in US2 and are release blockers under
   Principle II. US1 alone is suitable for TestFlight.

### Incremental Delivery

1. Setup + Foundational → shared types and a running service.
2. US1 → alerts arrive (TestFlight).
3. US2 → control and privacy complete; releasable with v2.0.
4. US3 → test notification and season note.
5. Polish → quickstart, label decision, PR.

---

## Notes

- [P] tasks touch different files and depend on no incomplete task.
- Commit after each task or logical group; every commit builds and passes tests on macOS and
  Linux.
- After the initial release, work merges to `main` only through a PR (constitution workflow).
