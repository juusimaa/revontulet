# Implementation Plan: Aurora Alerts

**Branch**: `002-aurora-alerts` | **Date**: 2026-10-24 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-aurora-alerts/spec.md`

## Summary

Opt-in push alerts when the chance to see the aurora in the user's coarse zone reaches their
threshold. A zone is the area around one of the 10 magnetometer stations. The app works out the
zone on the device from the place it already resolves and registers only an APNs token, the zone
and the threshold with a small alert service. The service is a Swift package that reuses
`AuroraCore` on Linux (verified: the core's 76 tests pass in a Linux container). Every 5 minutes
it computes each zone's chance with exactly the app's rules, applies fixed repeat rules, and
sends localisation-key payloads so it never learns the user's language. It runs as its own
container on the existing UpCloud server behind the existing Caddy, with no access log, and is
monitored by a heartbeat. The app and all other features never depend on it. See
[research.md](research.md).

## Technical Context

**Language/Version**: Swift 6.4 (app, Xcode 27.1); Swift 6.4.1 on Linux for the service
(`swift:6.4.1-noble`); Swift 6 language mode, strict concurrency everywhere.

**Primary Dependencies**: App: SwiftUI, UserNotifications, UIKit app delegate adaptor for APNs
registration; still no third-party code. Service: Hummingbird 2.28, APNSwift 7.1
(`kylebrowning/APNSwift`), SQLiteNIO 1.13, AsyncHTTPClient 1.36 (R3).

**Storage**: Service: one SQLite file (`registrations`, `zone_alert_state`) on a host volume, nightly
self-overwriting backup. App: `AlertSyncState` in UserDefaults.

**Testing**: Swift Testing in `AuroraCore` (zones, `AlertPolicy` reference cases, `ZoneEvaluator`
with recorded fixtures, message keys, validation, `AlertSync` with a fake API) on macOS and Linux;
Swift Testing in `Server` (routes with an in-memory store, dispatch with a fake APNs sender,
circuit breaker, retention sweep); app unit test that every alert key exists in fi/sv/en;
XCTest UI tests for the settings states with a stub alert API.

**Target Platform**: iOS 26.0+ (iPhone); Linux x86_64 container (`linux/amd64`, server
architecture confirmed, R4).

**Project Type**: Mobile app + portable Swift package + small web service.

**Performance Goals**: Alert on the device within 15 min of FMI data (SC-001): evaluation every
5 min, send within the cycle. Cycle for 10 zones well under 1 s of CPU. Service memory < 100 MB
(limit 150 MB).

**Constraints**: FMI usage limits (service: 12 magnetometer + 6 cloud requests per hour, for all
users together); stores only FR-013's fields; no request or access logging; EU hosting; no
background location; no app feature depends on the service; alerts never sent late (20 min).

**Scale/Scope**: 10 zones; up to tens of thousands of registrations; 3 HTTP endpoints plus
health; 1 settings screen, 1 toolbar button, 11 notification strings in 3 languages.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.* Checked against
constitution v1.1.0.

| Principle | Check | Status |
|---|---|---|
| I. Open Data Only | Service uses the same FMI open data sets as the app via the same core client, fetched once per cycle for all users (18 requests/hour); no new data source. | Pass |
| II. Privacy by Design | Off by default; nothing sent before opt-in. Stores exactly the four fields Principle II lists: token, zone, threshold, day-rounded confirmation time; no zone history, IP, language or device details; no request/access logs. Deletion on opt-out, on revoked permission, on invalid token, after 180 days. Hosted at UpCloud in Helsinki, named in the privacy policy. Privacy label deviation justified in the spec's Privacy Review. | Pass |
| III. Shared Core, Native Shells | Zones, zone evaluation, alert rules, message keys, HTTP contract types and device sync are in `AuroraCore`; core verified on Linux; the service and the app are thin shells. Linux build/test added to CI. | Pass |
| IV. Test-First | `AlertPolicy` reference cases, `ZoneEvaluator` with recorded fixtures, validation and sync logic written test-first in the core; service dispatch rules test-first with fakes. | Pass |
| V. Performance & Efficiency | No background work for alerts in the app (pushes wake nothing; sync only on foreground); no background location; service polls no faster than FMI publishes. | Pass |
| VI. Native, Polished UX | Settings states designed explicitly ([alert-settings-states.md](contracts/alert-settings-states.md)); built with `ios-ui-craft`; Dynamic Type, VoiceOver, no colour-only state; system notification permission flow. | Pass |
| Constraints | One alert backend, opt-in; app works identically without it; missed alerts not sent late; monitored; no accounts. Server dependencies justified (R3), licences AGPL-compatible. | Pass |
| Workflow | Feature branch `002-aurora-alerts` and PR with the Constitution Check, as required after the initial release. | Pass |

**Post-design re-check (after Phase 1)**: Pass. `/speckit-analyze` found that an earlier draft
stored each token's APNs environment as a fifth field; this was removed. Each service instance
now sends to one APNs environment set by configuration: the production instance on the server
for TestFlight and App Store builds, and a separate development instance (sandbox) for builds run
from Xcode (R5).

## Spec amendments from research

Applied to [spec.md](spec.md) in this planning step:

- **FR-008 / SC-003 / Key Entities**: repeat and nightly-cap state is kept per zone, never per
  device; the cap is "3 per night from its zone" (R8).
- **Edge cases**: APNs does not report notifications turned off in iOS Settings; the app checks
  permission on open and deletes the registration (R7).
- **SC-002**: at least 3 of the 20 reference nights are recorded FMI data; the rest are synthetic
  sequences of zone conditions (from `/speckit-analyze`).
- **Privacy Review**: label proposal now includes Device ID besides Coarse Location; linked vs not
  linked is left for the release decision (R11).

## Project Structure

### Documentation (this feature)

```text
specs/002-aurora-alerts/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── alert-api.md                 # HTTP API v1
│   ├── alert-rules.md               # zone evaluation, repeat rules, reference cases
│   ├── push-notification.md         # APNs request, payload, keys, response handling
│   ├── aurora-core-alerts-api.md    # core additions
│   └── alert-settings-states.md     # settings screen states
├── checklists/requirements.md
└── tasks.md                         # created by /speckit-tasks
```

### Source Code (repository root)

```text
Packages/AuroraCore/                       # shared, portable (macOS, iOS, Linux)
├── Sources/AuroraCore/
│   ├── Alerts/                            # NEW
│   │   ├── AlertZones.swift               # AlertZone, zone(for:previous:)
│   │   ├── ZoneEvaluator.swift            # per-zone conditions from FMI data
│   │   ├── AlertPolicy.swift              # repeat rules, nightly cap, late-data drop
│   │   ├── AlertMessage.swift             # loc keys per level/reason
│   │   ├── AlertAPIModels.swift           # RegistrationUpsert, RegistrationToken, validation
│   │   └── AlertSync.swift                # device-side desired/confirmed sync, AlertAPI protocol,
│   │                                      #   URLSession-backed client
│   └── … (existing, unchanged)
└── Tests/AuroraCoreTests/
    ├── Alerts/                            # NEW: policy reference cases, zones, evaluator, sync
    └── Fixtures/alerts/                   # NEW: recorded FMI responses for strong/quiet nights

Server/                                    # NEW: alert service (thin shell)
├── Package.swift                          # depends on ../Packages/AuroraCore + R3 libraries
├── Sources/
│   ├── AlertServer/                       # library: routes, SQLite store, APNs dispatcher,
│   │                                      #   evaluation loop, retention sweep, heartbeat, rate limits
│   └── alert-service/                     # executable: configuration from environment, startup
├── Tests/AlertServerTests/
├── Dockerfile                             # build swift:6.4.1-noble, run ubuntu:noble (R4)
└── deploy/
    ├── compose.yaml                       # edge network, mem_limit 150m, secret, volume
    └── revontulet-alerts.caddy            # reverse_proxy only, no access log

Revontulet/                                # iOS app
├── Alerts/                                # NEW: AlertSettingsView, AlertSettingsModel
├── Platform/                              # NEW: PushRegistration (app delegate, token),
│                                          #   NotificationPermission, UserDefaultsAlertSyncStore
├── MainScreen/                            # bell toolbar button; zone update when place resolves
├── App/                                   # wiring; alerts base URL from build setting
├── Revontulet.entitlements                # NEW: aps-environment
└── Resources/Localizable.xcstrings        # alert.* keys in fi, sv, en

.github/workflows/alert-service.yml        # NEW: core tests on Linux, server tests, image → GHCR
project.yml                                # push capability, entitlements, ALERTS_BASE_URL
docs/privacy.md                            # alerts section (FR-019)
```

**Structure Decision**: The shared logic grows inside `AuroraCore` under `Alerts/`, so the app,
the service and a future Android app use one implementation. The service is a separate Swift
package in `Server/`, depending on the core by path, so its server-only dependencies never reach
the app. Deployment files live with the service, and the image is built by a new GitHub Actions
workflow, the way the server's other apps are shipped. The app adds an `Alerts/` feature folder
and platform adapters, following the existing layout.

## Complexity Tracking

No constitution violations to justify. The new top-level `Server/` package is the backend that
constitution v1.1.0 allows; it is kept separate from `AuroraCore` so that its dependencies never
reach the app or the portable core.
