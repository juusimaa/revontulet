# Revontulet Constitution

Revontulet is a native iOS app that shows the probability of seeing the aurora borealis at the
user's current location, based on the R value calculated from open data published by the
Finnish Meteorological Institute (FMI, fmi.fi). An Android version may follow later.

## Core Principles

### I. Open Data Only

- Aurora, magnetometer, weather and any other science data MUST come from free, openly licensed
  sources. FMI open data is the primary source.
- Data licence terms (e.g. CC BY 4.0 attribution) MUST be honoured, and attribution MUST be shown
  in the app.
- The app MUST NOT depend on paid, proprietary or scraped data sources. A new data source MUST be
  documented in the feature spec with its licence and terms of use before it is used.
- Requests to FMI MUST respect its published usage limits and MUST NOT poll more often than the
  data actually updates.

Rationale: the app's value and credibility rest on transparent, reproducible public data.

### II. Privacy by Design

- Location MUST be processed on the device. Precise coordinates MUST NOT leave the device; any
  network request may include at most what the data source needs (e.g. a station ID or a coarse
  region).
- The app MUST request the least location access that works ("When In Use", reduced accuracy
  where sufficient) and MUST still function, with a manually chosen location, if access is denied.
- No analytics, advertising, tracking or third-party SDKs that collect user data. No accounts.
- A future backend (e.g. for push notifications) MUST be opt-in, MUST receive only the minimum
  data needed (coarse region, push token), and MUST be specified and reviewed against this
  principle before it is built.
- The App Store privacy label MUST be able to state "Data Not Collected", or the deviation MUST be
  justified in the relevant spec.

Rationale: an app that only needs to know roughly where the user is has no reason to collect more.

### III. Shared Core, Native Shells

- Domain logic — FMI data fetching and parsing, R value calculation, probability estimation and
  caching rules — MUST live in a separate Swift package with no dependency on SwiftUI, UIKit or
  other Apple-only UI frameworks, and with Foundation use limited to what is available on
  non-Apple platforms.
- Platform-specific code (UI, location services, notifications, widgets) MUST stay in thin native
  layers that talk to the core through clearly defined interfaces.
- The core MUST be buildable and testable on its own (`swift build`, `swift test`) without the
  app target.

Rationale: keeping the core free of UI and Apple-only frameworks lets an Android app reuse it
(e.g. via Swift on Android) or port it mechanically, while both apps stay fully native.

### IV. Test-First Where Feasible

- Core domain logic (parsing, R value calculation, probability, caching) MUST be developed
  test-first: write the test, see it fail, then implement.
- Calculations MUST be verified against known reference values from recorded FMI data; tests MUST
  use recorded fixtures, not live network calls.
- UI and platform-integration code SHOULD have tests where practical (view models, UI tests for
  the main flows); when tests are skipped, the reason MUST be noted in the task or plan.
- All tests MUST pass before a commit to `main`.

Rationale: a wrong probability is worse than none; the numeric core is where tests pay off most.

### V. Performance & Efficiency

- On launch, the last known result MUST be shown from cache immediately, before any network data
  arrives, and SHOULD appear within 1 second on supported devices.
- Network and location use MUST be minimal: fetch only what is needed, cache aggressively, and
  avoid continuous location tracking.
- Background work (refresh, widgets, future notifications) MUST use system-scheduled APIs and stay
  within platform energy budgets.
- Main-thread work MUST be limited to UI; parsing and calculation MUST run off the main actor.

Rationale: users open the app on a cold night to make a quick decision; it must be instant and
must not drain the battery.

### VI. Native, Polished UX

- The UI MUST follow Apple's Human Interface Guidelines and use current system design language
  (Liquid Glass, system materials, SF Symbols) instead of custom imitations.
- The main screen MUST answer "Should I go outside and look?" at a glance; supporting detail
  (R value, data time, source) MUST be available without crowding it.
- Every screen MUST support Dynamic Type, VoiceOver, Dark Mode and Reduce Motion / Reduce
  Transparency.
- Loading, offline, stale-data and permission-denied states MUST be designed explicitly, never
  left as blank or broken screens. Data age MUST always be visible.
- UI/UX design and implementation work (new screens, components, redesigns, visual polish) MUST
  use the `ios-ui-craft` skill, including its screenshot-driven visual iteration.

Rationale: a sleek, honest, accessible UI is the product; the data is only useful if it is
understood instantly.

## Technology & Platform Constraints

- Language: Swift 6 with strict concurrency checking enabled. UI: SwiftUI.
- Platform: iOS, targeting the current iOS release with Liquid Glass (iOS 26 or later). Widgets
  and other system surfaces are in scope as features, subject to the principles above.
- Dependencies: Swift Package Manager only. Third-party dependencies MUST be justified in the
  plan and kept to a minimum; none may violate Principle II.
- Backend: none. The architecture MUST NOT prevent adding a small backend later for push
  notifications (Principle II applies when it is added).
- Android: out of scope until the iOS app is released; Principle III keeps the path open.
- Licence: all code is AGPL-3.0; dependencies MUST have compatible licences.

## Development Workflow

- Features follow the Spec Kit flow: specify → (clarify) → plan → tasks → implement. Every plan
  MUST include a Constitution Check against these principles.
- Until the initial release, work is solo and committing directly to `main` is allowed. Every
  commit to `main` MUST build and pass all tests.
- After the initial release, changes MUST go through a feature branch and pull request, even when
  working alone, and the Constitution Check MUST be confirmed in the PR description.
- Releases are tagged with semantic versions.

## Governance

- This constitution overrides other practices and conventions in this repository. Where a spec or
  plan conflicts with it, the constitution wins until it is amended.
- Amendments are made with `/speckit-constitution`, recorded in a commit that explains the change,
  and versioned semantically: MAJOR for removing or redefining a principle, MINOR for adding a
  principle or materially expanding guidance, PATCH for clarifications and wording.
- Any deliberate deviation from a principle MUST be recorded in the plan's Complexity Tracking
  (or equivalent) with the reason and the simpler alternative that was rejected.
- Compliance is reviewed at every plan (Constitution Check) and, after the initial release, at
  every pull request.

**Version**: 1.0.0 | **Ratified**: 2026-10-22 | **Last Amended**: 2026-10-22
