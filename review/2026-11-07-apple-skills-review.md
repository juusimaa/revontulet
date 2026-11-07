# Codebase review, 2026-11-07 (apple-skills)

Read-only review. Five workers (Sonnet ×4, Haiku ×1) each checked a separate set of files, and Opus reviewed the app wiring, the platform code and the server. Opus re-checked every high finding and the main medium findings against the code.
Sections below: Verified priorities first, then the worker reports in full.

## Verified priorities

| # | Severity | Finding | Where | Verified |
|---|---|---|---|---|
| 1 | High | AlertSync writes a stale state copy back after `await api.*`. Turning alerts off while a PUT is in flight comes back as "on", and the delete is never sent. A new token or zone can be lost the same way. | Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertSync.swift:218-268 | Yes (2 workers independently, plus Opus) |
| 2 | High | Server: a dozen fake hex tokens in a zone trip the bad-token circuit breaker, which stops sending, keeps the fake tokens and doesn't save state, so alerts stop for good | Server/Sources/AlertServer/Dispatcher.swift:81-95 | Yes (Opus) |
| 3 | Medium | OutlookService.loadCacheOnce sets its flag before the await, so an old disk read can overwrite freshly fetched inputs | Packages/AuroraCore/Sources/AuroraCore/Outlook/OutlookService.swift:110-121 | Yes |
| 4 | Medium | Alert settings: a 400 rejection is never shown ("Waiting to confirm" forever); an APNs registration failure is silent and not retried | Revontulet/Alerts/*, Revontulet/Platform/PushRegistration.swift | Worker |
| 5 | Medium | Map page: the spinner never ends if the first station fetch fails; staleness is not shown | Revontulet/MainScreen/StationMapPage.swift | Worker |
| 6 | Medium | Sky TimelineView keeps animating at 15 fps behind the opaque map page and sheets (battery) | Revontulet/MainScreen/SkyBackground.swift:20, MainScreenView.swift:36 | Yes |
| 7 | Medium | Privacy manifest declares no collected data, but alerts send a coarse location-derived area | Revontulet/Resources/PrivacyInfo.xcprivacy | Yes (your call) |
| 8 | Medium | 12-minute magnetometer window leaves ~110-140 s of slack for FMI publishing lag | Packages/AuroraCore/Sources/AuroraCore/FMI/FMIRequests.swift:13 | Arithmetic yes; real lag unknown |
| 9 | Medium | Cancellation mapped to `.offline`; a cancelled outlook refresh still saves | AuroraCore AuroraService/OutlookService | Worker |
| 10 | Medium | PlacePickerView searches and sorts in `body`; solar math in `body` every 30 s | Revontulet/PlacePicker, MainScreen | Worker |
| 11 | Low | Many accessibility details (VoiceOver labels drop visible text, heading traits, Dynamic Type caps, Reduce Motion) | see view and alerts reports | Worker |
| 12 | Low | Server: rate limit per full IPv6 address; sequential APNs sends; duplicate alerts after a database error mid-cycle | Server/Sources/AlertServer | Opus |
| 13 | Low | Tests: 26 force unwraps where `#require` fits, 20 UI queries by visible text, 2 polling waits, 6 uses of `.now` | see tests report | Spot-checked |

Probably intentional, verify on device: `.environment(\.colorScheme, .dark)` vs `.preferredColorScheme` (MainScreenView:58). The code passes the system scheme to the background on purpose.


---

# Opus review: app wiring/platform (4) and server (6)

## Server

### [high] Fake registrations can stop every alert (bad-token circuit breaker)
File: Server/Sources/AlertServer/Dispatcher.swift:81-93, EvaluationLoop.swift:85-89
Problem: PUT /v1/registration accepts any well-formed lowercase hex token. APNs answers BadDeviceToken for made-up tokens. If a zone has more than max(10, 10 % of recipients) such tokens, dispatch returns `.badDeviceTokens` before sending to the rest, the bad tokens are kept (deleted only when failure == nil), and the cycle does not save state. Every later cycle trips the breaker again, so alerts stop for good. 11 PUTs are well within the 30 per 10 minutes per-address limit. The heartbeat fails, but nothing recovers on its own.
Fix: keep sending to every recipient when bad tokens show up. Apply the breaker only to the *deletion* step (don't delete when the share is high) and report the failure to the heartbeat. Save state when anything was delivered. Optionally, delete bad tokens whose registration was confirmed on the current UTC day even when the breaker trips: a misconfigured environment hits old registrations, while a flood of fakes is all new.

### [low] Rate limit bypassable over IPv6
File: Server/Sources/AlertServer/RateLimiter.swift:76
Problem: the limiter is keyed by the full client address. A single IPv6 /64 gives one host 2^64 addresses, which makes the per-address limit (and so the fake-registration flood above) unlimited.
Fix: key IPv6 addresses by their /64 prefix.

### [low] Sequential APNs sends
File: Server/Sources/AlertServer/Dispatcher.swift:70
Problem: one awaited HTTP/2 request at a time, plus a retry. With thousands of registrations a cycle can exceed the 20-minute delivery window and the 5-minute interval.
Fix: send with a TaskGroup at bounded concurrency (for example 20); the HTTP/2 connection multiplexes.

### [low] A database error mid-dispatch resends the same alerts next cycle
File: Server/Sources/AlertServer/EvaluationLoop.swift:84-94
Problem: if `store.delete` or `saveZoneState` throws after pushes went out, the in-memory `states` is not updated, so the next cycle sends the same decision again. collapse-id replaces the earlier notification, but it still plays a sound a second time.
Fix: assign `self.states = states` right after a dispatch without a failure, before the database writes.

## App wiring and platform

### [medium] Privacy manifest says no data is collected, but alerts send a coarse area
File: Revontulet/Resources/PrivacyInfo.xcprivacy (NSPrivacyCollectedDataTypes is empty); project.yml NSLocationWhenInUseUsageDescription
Problem: with alerts on, the app sends one of ten location-derived areas with a push token to the developer's server. Under Apple's definitions, that is "Coarse Location" collected for App Functionality, not linked and not used for tracking. docs/privacy.md already says this honestly, but the manifest and the App Store privacy label should match it. The location usage string ("It is never sent anywhere") is also slightly too strong.
Fix: declare NSPrivacyCollectedDataTypeCoarseLocation (Linked false, Tracking false, purpose AppFunctionality), and make the same change in App Store Connect. Reword the string to something like "…Only a coarse area is shared if you turn on aurora alerts."
Judgment call: yours to decide.

### [low] `didRefreshHeadline` is shared between an abandoned refresh and its replacement
File: Revontulet/MainScreen/MainScreenModel.swift:77, 218, 280
Problem: `choose(_:)` cancels the running refresh task and starts a new one. The cancelled task keeps running until its next check, and both tasks write the same `didRefreshHeadline`. Today this is harmless (the cancelled task skips `refreshStations`), but it's fragile.
Fix: make it a local in the task closure, passed to or returned from `refreshOnce`.

### Checked, no issues
- RevontuletApp scene wiring: `@State` is private, and `.task(id: scenePhase)` cancels on background.
- LocationProvider: CLServiceSession is invalidated in `defer`, the TaskGroup timeout doesn't count permission-prompt time, and PermissionFlag uses a Mutex.
- File caches: atomic writes, excluded from backup, decode failures fall back to nil.
- PlaceSelectionStore, AlertConfiguration: a deliberate `preconditionFailure` on a build-config error.
- MainScreenModel: `@Observable @MainActor`, staleness guards after every await, and refresh coalescing is correct.
- Server: no request logging, and the logger is clamped to info or above. SQL is parameterized. Caddy replaces client-supplied X-Forwarded-For (untrusted clients), so the first entry is the real address. No published ports. Body size is capped. APNs payload matches the contract. `confirmedAt` vs Unregistered timestamp handling is correct.

---

# Review 3: Alerts (settings model/view, permission, push registration, store)

## Findings

### [severity: high] Actor reentrancy in AlertSync.send overwrites newer user changes (turn-off can flip back to on)
File: Packages/AuroraCore/Sources/AuroraCore/Alerts/AlertSync.swift:218-253 (context file). Triggered by calls from Revontulet/Alerts/AlertSettingsModel.swift:123-165 and 167-170.
Rule/source: guide-swift-concurrency, actor reentrancy. State read before an `await` must not be written back after it.
Problem: `send` snapshots `var state = await current()`. It then awaits `api.upsert` or `api.delete`, which are network calls and can take seconds. While it is suspended, the model calls `setDesired(.disabled)`, `tokenChanged`, `zoneChanged` or a threshold change. Each of those updates `loaded` and starts its own `send`. When the first `send` resumes, it writes `state.confirmed = state.desired; update(state)` using the OLD snapshot. That overwrites the user's newer `desired`, `token` and `zone`.
- Example: the user taps "Turn off alerts" while the 15 s retry tick or the on-foreground sync is mid-upsert. Alerts silently turn back on, and the server registration is left as it was.
- Example: the APNs token arrives during the turn-on upsert. The stored token is reverted and the new registration is never made.
- Several model entry points run in separate unstructured Tasks, so this is reachable in practice: `runWhileActive`, `tokenReceived`, `placeResolved`, `thresholdChanged`.
Suggested fix: after each await, re-read `current()` and apply only the confirmation fields, or serialise sends.
```swift
let sent = state.desired
try await api.upsert(...)
var fresh = await current()           // not the stale snapshot
fresh.confirmed = sent
fresh.confirmedToken = token
fresh.confirmedAt = now
await update(fresh)
```
The same applies to the `.disabled` branch and the stale-token loop. Alternatively, wrap `send` in a single in-flight task or a queue.

### [severity: medium] Service rejection (400) is never shown; the UI says "Waiting to confirm" forever
File: Revontulet/Alerts/AlertSettingsModel.swift:61-66, 82
Rule/source: task brief, "error states the UI never shows".
Problem: `AlertSyncState.rejection` is set on 400 and stops further retries. The model never exposes it. `phase` is `.on(confirming: syncState.isPending)`, and `isPending` stays true because `confirmed != desired`. The user sees a spinner and "Waiting to confirm" permanently, and `sendTest` is hidden because `!confirming` is false. The comments say "service failures never surface", but a non-retryable rejection is not a transient failure.
Suggested fix: expose `var isRejected: Bool { syncState.rejection != nil }` and render a state, for example "Couldn't register. Update the app or change the area", with the spinner stopped. At minimum, stop animating the rotate symbol when `rejection != nil`.

### [severity: medium] APNs registration failure is silent and is not retried while the app is open
File: Revontulet/Platform/PushRegistration.swift:34, 43-45; Revontulet/Alerts/AlertSettingsModel.swift:99-112, 172-176
Rule/source: usernotifications, `registerForRemoteNotifications` and `didFailToRegisterForRemoteNotificationsWithError`.
Problem: `registerForRemoteNotifications` is called only in `turnOn` and once at `didFinishLaunching`. It fails with no connectivity, which is common on the first launch or right after turn-on. The failure handler is empty, and `runWhileActive` never re-requests. With no token, `AlertSync.send` breaks out silently. The user stays on "Waiting to confirm" until a full relaunch. A long-lived app is never asked for a fresh token on foreground either.
Suggested fix: in `runWhileActive`, and again in the retry loop, call `if syncState.isOn, syncState.token == nil { push.register() }`. Also call `push.register()` on each foreground while on, which is cheap and idempotent. Log the error in `didFailToRegister`.

### [severity: medium] Persisted state decode failure silently resets everything and orphans the server registration
File: Revontulet/Platform/UserDefaultsAlertSyncStore.swift:6-12
Rule/source: task brief, "UserDefaults keys and Codable versioning".
Problem: `try? JSONDecoder().decode(...)` returns a blank `AlertSyncState()` on any failure. `AlertSyncState` uses synthesized Codable.
- Adding a non-optional field in a later release (the struct already has several), or renaming or adding an enum case in `Desired` or `AlertThreshold`, makes every existing user's decode fail.
- Alerts then silently turn off, with no UI explanation. The token and `confirmedToken` are lost, so the server registration is never deleted. That is a privacy leak: the server keeps the token and zone while the app shows "Off".
- `save` also swallows encode errors.
- The key `alertSyncState` has no version.
Suggested fix: version the payload and decode leniently.
```swift
struct Envelope: Codable { var v = 1; var state: AlertSyncState }
// AlertSyncState: custom init(from:) using decodeIfPresent(...) ?? default for every field
```
On failure, keep the raw data and migrate it or log it. Add a test that decodes a fixture from the current release.

### [severity: low] Cold launch from a notification tap can miss `.auroraAlertOpened`
File: Revontulet/Platform/PushRegistration.swift:56-62
Rule/source: usernotifications, delegate timing.
Problem: on a cold launch from a tap, `didReceive` can fire before `MainScreenView`'s `onReceive` subscribes, because `NotificationCenter.post` is not buffered. The refresh-on-open is lost. The app still fetches at launch, so the impact is small.
Suggested fix: set a flag on the delegate or an `AppDependencies` property that the main screen reads on appear. Alternatively, use `AsyncStream`/`@Observable` state instead of a broadcast.

### [severity: low] `runWhileActive` restarts on every inactive/active flip and bypasses the backoff
File: Revontulet/Alerts/AlertSettingsModel.swift:99-103 (called from Revontulet/App/RevontuletApp.swift:18)
Rule/source: guide-swift-concurrency, task lifetimes. `.task(id: scenePhase)` cancels and restarts the task.
Problem: pulling down Control Center or Notification Center, the system permission prompt, and app-switcher peeks each go inactive then active. Each restart runs `checkPermission` and `sync.sync`, and `sync` clears `retryNotBefore`. While the server is down, this fires a request on every flip, which defeats the 30 s / 2 min / 10 min backoff.
Suggested fix: do the foreground work only when the phase goes from background to active, or make `sync` honour a minimum interval for the non-forced path.

### [severity: low] `requestAuthorization` errors are swallowed with no feedback, and a stale `.sent`/`.tryAgain` test status persists
File: Revontulet/Platform/NotificationPermission.swift:27-29; Revontulet/Alerts/AlertSettingsModel.swift:123-133, 141-150
Rule/source: task brief, "error states the UI never shows".
Problem:
- `try?` turns a thrown error into `false`. If the status stays `.notDetermined`, `turnOn` returns and the UI goes back to "Turn on alerts" with no explanation.
- `testStatus` is never reset after `.sent`, `.tryAgain` or `.failed`, except by `turnOff`. After a sheet reopen or a long time, "Test alert sent" and "Try again at 21:40" are shown stale.
Suggested fix: keep the thrown error and show a short message, or at least re-read the status. Clear `testStatus` in `.task`/`onDisappear`, or expire `.tryAgain` once the date has passed.

### [severity: low] Authorization status ignores the per-alert setting
File: Revontulet/Platform/NotificationPermission.swift:20-24
Rule/source: usernotifications, `notificationSettings().alertSetting`.
Problem: `.authorized` with Banners, Lock Screen and Notification Center all disabled (`alertSetting == .disabled`) and sound off is treated as `.allowed`. The user sees alerts "On", but nothing is visible to them.
Suggested fix: treat `.authorized` with `alertSetting == .disabled` as `.denied`, or show a hint.

### [severity: low] Accessibility: title lacks a heading trait; bouncy animations ignore Reduce Motion
File: Revontulet/Alerts/AlertSettingsView.swift:24-26, 132-141
Rule/source: HIG accessibility.
Problem: "Aurora alerts" is a plain `Text`, so it is not a heading for the rotor. The `.animation(.bouncy, ...)` modifiers and `withAnimation(.bouncy)` (line 162) do not check `accessibilityReduceMotion`. The spinner symbols do check it.
Suggested fix: add `.accessibilityAddTraits(.isHeader)` to the title and the section labels. Gate the animations on `reduceMotion`, for example `.animation(reduceMotion ? nil : .bouncy, value:)`.

## Checked, no issues
- Correctness checklist: `@Observable` is `@MainActor` and `@Bindable` is used for the injected model. There are no `@State` misuses, `.animation` always has `value:`, `ForEach` over `AlertThreshold.allCases` has stable identity, and there is no `AnyView`.
- Continuations: none are used in these files. The async `requestAuthorization` and `notificationSettings` APIs are used, so there are no double or missing resumes.
- scenePhase and revoked permission: `RevontuletApp.swift:18` re-runs `checkPermission` on every return to the foreground. A revocation while backgrounded is handled via `permissionRevoked`, which turns alerts off and deletes the registration. Server-side deletion necessarily waits for foreground.
- Token format: lowercase hex `%02x`. The comment states the server expects this. `tokenChanged` queues the old token for deletion. The token is sent only after opt-in, and no token is logged.
- The `@MainActor` delegate completion-handler versions in `PushRegistration` are correct. The `@preconcurrency` conformance is justified in the comment, and the completion handlers are called once.
- The race between `turnOn` registering and the token arriving is safe: `tokenChanged` stores the token whether or not `desired` is set yet.
- `onChange(of: model.threshold)` firing after `load()` is guarded by `thresholdChanged`'s equality check.
- Localization: all inspected strings have catalog entries, and interpolated strings use the `%@` form. The `LocalizedStringResource` keys exist. Dynamic Type is handled in `ThresholdOption`. The Link and `openNotificationSettingsURLString` usage is correct. `aps-environment` is in the entitlements.

---

# Review 5: AuroraCore sources

Read-only review of Packages/AuroraCore/Sources/AuroraCore (all ~40 files). `swift build` is clean (no warnings).
Paths below are relative to Packages/AuroraCore/Sources/AuroraCore.

### [severity: high] AlertSync writes a stale state snapshot back after `await api.*`, which can undo a user change
File: Alerts/AlertSync.swift:218-253 (also :255-262 `handle(.rejected)`, :193-215 `sendTest`)
Rule/source: guide-swift-concurrency, actor reentrancy: state read before an `await` and assumed unchanged after it.
Problem: `send` copies `var state = await current()`. It then suspends in `try await api.upsert(...)` or `api.delete(...)`. The actor is reentrant during that await. After it returns, the code mutates the old copy (`state.confirmed = state.desired`, `state.confirmedToken = token`, `staleTokens.removeAll`) and calls `update(state)`. That replaces the whole actor state with the old copy.
Exact scenario: alerts are enabled with zone OUJ and the PUT is in flight (slow network, up to 15 s). The user turns alerts off, so `setDesired(.disabled)` runs and stores `desired = .disabled`. The old PUT then returns 204, and `send` stores its old copy with `desired = .enabled(OUJ)` and `confirmed = .enabled(OUJ)`. The user's "off" is lost. The UI shows alerts on, and the `.disabled` branch never sends the delete, so the server keeps the registration and the user keeps receiving alerts. The same happens to a threshold or zone change, a `tokenChanged`, or a `staleTokens` append made during the await. `handle(.rejected)` and `sendTest(.notRegistered)` have the same pattern.
Suggested fix: after each await, re-read the current state and apply only the fields this operation owns. Only mark `confirmed` if `desired` still equals what was sent.
```swift
let sent = state.desired
try await api.upsert(...)
var latest = await current()          // re-read after the suspension
if latest.desired == sent {
    latest.confirmed = sent; latest.confirmedToken = token; latest.confirmedAt = now
}
await update(latest)
// stale-token loop: latest.staleTokens.removeAll { $0 == token } on a fresh read
```
Alternatively, serialise `send` (a "sending" flag plus a re-run request) so only one network operation is in flight.

### [severity: medium] AlertSync: `current()` loads the store twice, and concurrent `send`s race on the server
File: Alerts/AlertSync.swift:272-283 and :218
Rule/source: actor reentrancy (check-then-act across an await).
Problem 1: `current()` does `if let loaded {return}; let s = await store.load(); loaded = s`. Two first callers (for example `tokenChanged` and `zoneChanged` right after launch) both see `loaded == nil` and both load. Each mutates its own copy and calls `update`. The second `update` discards the first caller's change.
Problem 2: concurrent `send` calls (`setDesired` plus `sync` on foreground plus `retryIfDue`) can have two upserts in flight. For a quick sequence of changes A then B, the server may apply B then A, while local `confirmed` records B. The device then believes B is confirmed and only re-sends after the 24 h re-confirmation.
Suggested fix: load once with an in-flight Task, and serialise `send`.
```swift
private var loading: Task<AlertSyncState, Never>?
private func current() async -> AlertSyncState {
    if let loaded { return loaded }
    let task = loading ?? Task { await store.load() }
    loading = task
    let s = await task.value
    if loaded == nil { loaded = s }     // first resumer wins
    return loaded!
}
```

### [severity: medium] OutlookService.loadCacheOnce sets its guard flag before the await, so concurrent callers see an empty cache
File: Outlook/OutlookService.swift:110-121
Rule/source: actor reentrancy.
Problem: `loadedCache = true` is set before `await cache.load()`. A second caller (`refresh` and `cachedSnapshot()` are called concurrently at launch) returns immediately, while `previous`, `solarWind`, `kp`, `watches` and `clouds` are still empty. Effects:
- `cachedSnapshot()` returns nil although a snapshot is stored, so the UI flashes empty.
- `refresh` evaluates `isDue` against empty inputs and refetches everything. This loses the `previous` hysteresis state for `soon`.
- If the disk read finishes after the network fetches, the older cached inputs overwrite the fresher ones just fetched. The code that applies them (`solarWind = DueInput(...)` and so on) is unconditional.
Suggested fix: keep a `Task` for the load and await it from every caller.
```swift
private var cacheLoad: Task<OutlookSnapshot?, Never>?
private func loadCacheOnce() async {
    let task = cacheLoad ?? Task { await cache.load() }
    cacheLoad = task
    guard let cached = await task.value, !loadedCache else { return }
    loadedCache = true   // set synchronously with applying the values
    ...apply...
}
```

### [severity: medium] Cancellation is swallowed or converted into data errors
File: AuroraService.swift:99-105 and :52; Outlook/OutlookService.swift:124-127 and :66-98; Alerts/ZoneEvaluator.swift:30-38
Rule/source: guide-swift-concurrency, cancellation propagation.
Problem:
- `fetchMagnetometer` has `catch { throw AuroraServiceError.offline }`. A cancelled refresh (view disappears or the task is replaced) is reported as "offline", so the UI can show an offline error for a normal cancel.
- `try? client.cloudObservations` and `try? await http.get` also eat `CancellationError`.
- `OutlookService.refresh` never throws. After a cancel, every `fetch` returns nil, and the method still builds a snapshot from stale inputs, sets `previous = snapshot` and saves it to the cache. It overwrites the cached snapshot with a recomputed one, and `computedAt` looks fresh.
Suggested fix: rethrow cancellation, and check `Task.isCancelled` or call `try Task.checkCancellation()` before committing state.
```swift
do { magnetometer = (date, try await client.magnetometerSamples(now: date)) }
catch is CancellationError { throw CancellationError() }
catch let e as URLError where e.code == .cancelled { throw CancellationError() }
catch { throw AuroraServiceError.offline }
```
In `OutlookService.refresh`, add `try Task.checkCancellation()` and make the method `throws`, or `guard !Task.isCancelled` before `previous = snapshot; await cache.save(...)`.

### [severity: medium] The 12-minute magnetometer window leaves only about 2 minutes of slack for FMI latency
File: FMI/FMIRequests.swift:11-14 with Activity/RIndex.swift:28-34 and AuroraService.swift:114-123
Rule/source: HTTP/data-window correctness.
Problem: R needs 61 samples back to `latest - 600 s`, and at most 3 may be missing. The request starts at `now - 720 s`. If the newest FMI sample is more than about 150 s older than `now`, the oldest samples fall outside the request. With a lag of L seconds, `(L-120)/10` samples are missing, and R becomes nil for every station once that count exceeds 3. The result is `.noData` (or alerts silently stop), although FMI did have usable data. Real FMI delivery lag (1-3 min, longer during backfills or outages) can reach this.
Suggested fix: widen the window to 20-25 minutes. This is cheap, and the bbox response is small.
```swift
let start = ((end - 25 * 60) / 10).rounded(.down) * 10
```
The parser and `RIndex` already ignore samples outside the window.

### [severity: low] AuroraService.stationReadings does not actually share the in-flight fetch with refresh
File: AuroraService.swift:94-98 and :48-60 (doc comment says "sharing the fetch")
Rule/source: actor reentrancy.
Problem: `due` is decided before the `await`, and nothing records an in-flight fetch. When the map page and the main screen both call in (app launch) while `magnetometer == nil`, both fetch. This doubles FMI traffic and gives two possibly different sample sets. Whichever finishes last wins, even if its `date` is older.
A related point is that `previousStationID` is shared across places. Two interleaved `refresh(for:)` calls for different places overwrite each other's hysteresis. Two interleaved refreshes can also save out of order, so an older result can replace a newer one in the cache (`await cache.save`).
Suggested fix: keep `private var magnetometerTask: Task<[MagnetometerSample], Error>?`, reuse it while it is running, and clear it when it finishes. Only save the result if its `computedAt` is at least the cached one.

### [severity: low] A failed or empty cloud/magnetometer fetch overwrites the last good cache with nil or empty
File: AuroraService.swift:55-57, Alerts/ZoneEvaluator.swift:39-41, AuroraService.swift:99-102
Rule/source: cache invalidation.
Problem:
- `clouds = await cloudsFetch.map { ... }` assigns nil when the fetch failed, so the previous good observations are dropped. `OutlookService.DueInput` deliberately keeps the last good value. The comment ("until then clouds are unknown") shows the choice is intended, but clouds that are 11 minutes old then become unknown for a transient failure, and the chance level changes (for example "cloudsIncluded" flips).
- A magnetometer response with HTTP 200 and zero elements is stored with `fetchedAt = date`. Non-forced refreshes for the next 5 minutes then throw `.noData` without retrying.
Suggested fix: on failure keep the old tuple (`if let f = await cloudsFetch { clouds = (date, f) }`, optionally dropping it after a maximum age). Treat an empty element list as a failed fetch, or do not advance `fetchedAt`.

### [severity: low] `nightKey` is off by one hour around noon on the two DST-change days
File: Alerts/AlertModels.swift:45-52
Rule/source: Date/Calendar/TimeZone correctness (Europe/Helsinki DST).
Problem: the key subtracts 12 absolute hours and then reads the Helsinki date, instead of using the local wall-clock time. On the spring-forward day (2026-03-29), 12:00-13:00 EEST gives 09:00-10:00Z. Minus 12 h is 21:00-22:00Z on 28 March, which is 23:00-24:00 EET on 28 March, so the key is the previous date, but a time after noon should map to the current date. On the fall-back day (2026-10-25), 11:00-12:00 EET gives 09:00-10:00Z. Minus 12 h is 21:00-22:00Z on 24 October, which is 00:00-01:00 EEST on 25 October, so the key is the current date instead of the previous one. The effect is that the nightly alert counter resets an hour late or early at midday, when it is too light to alert. This is harmless in practice, but the code claims "before 12:00 counts as the previous date".
Suggested fix:
```swift
let c = helsinkiCalendar.dateComponents([.year,.month,.day,.hour], from: date)
var day = helsinkiCalendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
if c.hour! < 12 { day = helsinkiCalendar.date(byAdding: .day, value: -1, to: day)! }
// format day with helsinkiCalendar
```

### [severity: low] URLSessionHTTPClient sets `Accept-Encoding: gzip` by hand, which may disable automatic decoding on Linux
File: FMI/HTTPClient.swift:20
Rule/source: Linux portability (FoundationNetworking is a curl-backed URLSession).
Problem: on Darwin the transport decodes the response either way. In swift-corelibs-foundation, a manual `Accept-Encoding` header can leave libcurl's own decoding option unset or in conflict (this is from memory, not verified on a Linux build). The body would then reach `BsWfsParser` still gzipped and fail with `.malformedResponse`. The comment "Responses are gzip-decoded automatically" is only guaranteed when the library sets the header itself.
Suggested fix: remove the `httpAdditionalHeaders` line. URLSession already advertises gzip and decodes it. If the server build uses this client, confirm with one request on Linux.

### [severity: low] NOAA propagated solar wind parser requires `propagated_time_tag` although it is optional in use
File: NOAA/NOAAParser.swift:21-22
Rule/source: parser robustness.
Problem: the doc says columns are found "by name" so product changes are tolerated. But `propagated_time_tag` is required in the `guard`, and `arrival` is optional everywhere else (`SolarWindSample.arrival: Date?`). If SWPC renames or drops that column, the whole "soon" signal becomes `unknown` even though Bz and speed are still present.
Suggested fix: `let arrival = names.firstIndex(of: "propagated_time_tag")` (optional, as `density` already is), and use `cell(arrival)`, which already accepts nil.

### [severity: low] Minor timestamp and number validation gaps
File: FMI/UTCTime.swift:20-22; NOAA/NOAAParser.swift:146-152 (`NOAATime.parse`); FMI/BsWfsParser.swift:81 and :73; Alerts/URLSessionAlertAPI.swift:66
Rule/source: parser robustness.
Problem:
- `UTCTime.parse` accepts any day 1-31 in any month. "2026-02-31" rolls into March via `daysFromCivil`. It also rejects fractional seconds, which is documented.
- `NOAATime.parse` keeps only the first 19 characters. A timestamp with an offset (`+02:00`) is silently read as UTC.
- `BsWfsParser`: `Double(trimmed)` accepts `inf` and `-inf` (only NaN is filtered), unlike `JSONValue.number`, which uses `isFinite`. The `pos` numbers are not checked for finiteness.
- `Retry-After`: `TimeInterval("nan")` and `TimeInterval("inf")` parse. `inf` sets `rateLimitedUntil` to a date that never arrives, so `send` stays blocked until the app restarts. An HTTP-date value falls back to 60 s (acceptable). The server is trusted, so this is theoretical.
Suggested fix: validate the day against the month length. Use `.isFinite` in BsWfs and clamp: `min(max(TimeInterval(s) ?? default, 1), 3600)` for `Retry-After`.

## Checked, no issues
- Package builds clean on macOS with Swift 6 language mode; no compiler warnings.
- `nonisolated(unsafe)` on the three regex literals (NOAAParser.swift:94-96): immutable values, only read. The use is justified; there are no other `nonisolated(unsafe)` or `@unchecked Sendable` in the package.
- No `try!`. Force unwraps are safe: `URLComponents(string: endpoint)!` and `components.url!` (fixed input), `Int(...)!` on regex-constrained digits (NOAAParser:75-76), `byLevel[$0]!`, `components.year!`. `TimeZone(identifier: "Europe/Helsinki")!` is safe because the server image installs tzdata (Server/Dockerfile:27).
- No DateFormatter or ISO8601DateFormatter anywhere: `UTCTime` is a hand-written, locale-free parser and formatter (Hinnant algorithms; negative days handled by `floorDiv`). The two `Calendar` objects are created once as `static let`, so there is no per-call formatter cost.
- BsWfsParser: all indexing is bounds-safe (`byteRange` guards `count >= pattern.count`; `bytes[tagStart + 1]` has `tagStart < match.lowerBound`). Truncated elements throw `.malformedResponse` and an ExceptionReport is detected. The 2000-byte head check is fine (FeatureCollection sits at byte 44 in the fixtures). A malformed or empty input never traps.
- XMLParser is not used, so Linux is fine. `FoundationNetworking` is imported behind `#if canImport` in both URLSession files. Resources use `Bundle.module`, and the Dockerfile copies the `.resources` bundle.
- HTTP: timeouts are set on both clients (15 s per request, 30 s per resource). Non-200 gives `FMIError.httpStatus`. `URLSessionAlertAPI` uses an ephemeral session with `urlCache = nil` and sends tokens only in bodies. Status mapping (400/404/429/other) matches the contract. The server's delete is idempotent (204), so the client's 404 mapping does not loop.
- `FMIClient` station match caching (`[Coordinate: Station?]` with `?? closure`) caches nil correctly. The hysteresis and R computation are consistent.
- Sun and moon math: the NOAA and Meeus terms checked against the published tables (first 15 longitude terms and 14 latitude terms); the `normalized` 360.0 edge is handled by `% 8`; `acos` input is clamped. Elevation works for any longitude and for pre-1970 dates (modular `truncatingRemainder` with negative correction).
- Nights.swift and the polar edges: the logic uses UTC arithmetic only, with Helsinki used just for `localDate`, so DST cannot shift night boundaries. The 24 h cap on a night could give an empty relevant window in true polar night, but at the bundled stations' latitudes (at most 70.1 N) the sun never stays below -6 all day, so this cannot occur in Finland. At midsummer both nights are `.tooLight` and `nextDarkNight` is bounded at 120 days.
- AlertPolicy (re-arm, candidate, late-data, nightly cap) and AlertSeason are pure and consistent with the contract. ZoneEvaluator and AuroraService share logic.
- SoonCalculator and OutlookCalculator: window and median logic is safe (non-empty arrays before `median`), and Kp and cloud-hour keys match exactly (integer-second Dates).

---

# Review 2: Revontulet/MainScreen/StationMapPage.swift

Note: the file uses no MapKit. The "map" is a hand-drawn equirectangular Canvas plus a ForEach of buttons placed with .position. The MapKit checks (Map, MapCameraPosition, Annotation, bounds, deprecations) therefore do not apply. There is no pan or zoom, and no system map style.
The only projection risk is a station outside the hard-coded bounds (19.9...31.8 E, 57.9...70.15 N). All current stations are inside.
ios-dev Correctness Checklist: no violations found (see the end of this report).

### [severity: medium] Spinner forever when the first fetch fails (offline or error), with no empty or error state
File: Revontulet/MainScreen/StationMapPage.swift:28-39 (with MainScreenModel.swift:298-308)
Rule/source: the task brief ("behaves well when data is missing"); HIG feedback (always say why content is missing).
Problem: `readings == nil` always renders a ProgressView.
- In `refreshStations`, `.offline` only sets `isStationMapOffline = true`. Any other error leaves `stationReadings` nil.
- On a cold launch with no network, or after a generic failure, the page shows an endless spinner.
- The `isOffline` flag is passed in, but the nil branch ignores it. The `header` only shows "Not updating" next to a subtitle that says "Geomagnetic activity only". The spinner still implies loading is in progress.
- VoiceOver users get an unlabelled progress indicator indefinitely.
Suggested fix: add a failed state, for example by making the nil branch depend on `isOffline`:
```swift
if isOffline {
    ContentUnavailableView("No station data", systemImage: "wifi.slash",
                           description: Text("Pull to refresh when you are back online."))
} else { ProgressView().accessibilityLabel(Text("Loading")) }
```
The model should also expose a "failed" flag for non-offline errors, since they currently look the same as loading.

### [severity: medium] Staleness is invisible: time-of-day only, no date, no per-station age, and non-offline errors show no warning
File: Revontulet/MainScreen/StationMapPage.swift:85-90, 76-80, 93-98
Rule/source: the brief (stale data); app-internal contract in MainScreenModel.swift:306 ("the map says how old they are").
Problem:
- The subtitle uses `measuredAt.formatted(date: .omitted, time: .shortened)`. If the readings are hours or a day old, "Measured 21:40" reads as today.
- The "Not updating" label appears only for `.offline`. On a generic error the model keeps the old readings and sets `isOffline = false`. The map then shows old R levels with glows as if current, and the page's stated purpose is "are there auroras right now".
- The subtitle uses the newest `measuredAt` across stations. A station whose R is hours old still gets a full glow and marker, with no marker-level age cue.
- The default selection (the "most active" station) can be one that is stale.
Suggested fix: add an age check against `Date.now` (or an injected clock), and fall back to a relative or dated string when the age exceeds the threshold:
```swift
let age = now.timeIntervalSince(measuredAt)
age > 30*60
  ? "Measured \(measuredAt.formatted(.dateTime.weekday().hour().minute()))"
  : "Measured \(measuredAt.formatted(date: .omitted, time: .shortened))"
```
Show the warning label when `isOffline || isStale`. Consider treating readings older than about 30 minutes as `activity == nil` (dashed marker, no glow).

### [severity: low] The legend omits the "no data" marker, and that marker is low contrast
File: Revontulet/MainScreen/StationMapPage.swift:281-285, 260-262
Rule/source: HIG color/accessibility (do not rely on an unexplained symbol; non-text contrast of at least 3:1).
Problem:
- Dashed-ring markers (`activity == nil`) appear on the map but the legend lists only Probable, Possible and Unlikely.
- The dashed ring is white at 0.4 opacity, 1.5 pt wide. On the lighter light-mode sky (about #214559) that is about 3:1, and thinner strokes look worse. It is barely visible, and a missing station can look like a map drawing artifact.
Suggested fix: add `item(nil)` with the label "No data" (the key "No recent data" already exists). Raise the stroke opacity to about 0.6.
```swift
@ViewBuilder private var items: some View { item(.probable); item(.possible); item(.unlikely); item(nil) }
```
`item` would then take `ActivityLevel?`, and `hasData` would be derived from it.

### [severity: low] Station labels cap Dynamic Type and sit in a fixed 44 pt frame, so they can overlap neighbouring stations
File: Revontulet/MainScreen/StationMapPage.swift:225-233, 54
Rule/source: HIG accessibility (support Dynamic Type; hit targets should not overlap).
Problem:
- Labels are `.fixedSize()` and offset at a fixed 38 pt. They are capped at xLarge, which is a deliberate partial opt-out of larger text sizes, yet the rest of the page scales to AX sizes. Users on AX text get tiny map labels beside huge card text.
- Labels are part of the Button's label and not clipped, so the tappable area of one station can cover the label of another (for example Ivalo, Kevo and Kilpisjärvi at higher latitudes, which are close together). Taps in an overlap hit whichever button is on top (the later sibling).
- No collision handling exists beyond left or right flipping.
Suggested fix: keep the label out of the hit area and let VoiceOver and the card carry the name at AX sizes. For example, put `.allowsHitTesting(false)` on the label overlay, and apply `.contentShape(.circle)` or a smaller shape to the 44 pt frame. At accessibility sizes (`dynamicTypeSize.isAccessibilitySize`), hide the labels and rely on the selected station card.

### [severity: low] VoiceOver order and context for the markers
File: Revontulet/MainScreen/StationMapPage.swift:125-131, 134-135, 236-238
Rule/source: HIG accessibility (logical reading order; announce state changes).
Problem:
- Markers are exposed in `readings` order (service order, probably unrelated to geography or activity). Selecting a marker updates the card below, but no announcement is made.
- The button has no hint or trait to say that it selects the station and shows details.
- The legend is hidden, which is fine because each marker carries its level in `accessibilityValue`.
Suggested fix:
```swift
.accessibilityHint(Text("Shows details below"))
.accessibilitySortPriority(Double(reading.rank))   // most active first
```
After a selection, post `AccessibilityNotification.Announcement`, or keep the card focusable via `@AccessibilityFocusState`.

### [severity: low] Per-render work in `body` and a duplicated page tree
File: Revontulet/MainScreen/StationMapPage.swift:21-27, 53-56, 86, 95
Rule/source: guide-swiftui-performance-audit (do not compute in `body`; avoid doubled subtrees).
Problem:
- `ViewThatFits` builds and measures both page variants, so `StationMap` (with a GeometryReader and 10 markers) and `StationCard` are instantiated twice.
- `selected(in:)` runs twice per `page()` call, and `subtitle` does filter+map+max on every body. At 10 stations this is negligible; no per-frame recomputation exists, and the Canvas is static.
- `FinlandOutline.path` and `estoniaCoast` are rebuilt in the Canvas closure on every redraw (every size or selection change). Cheap at about 70 points.
Suggested fix: optional. Compute `selected` once at the top of `page()` (`let current = selected(in: readings)`), and cache the unscaled outline `Path` in a static. Keep the ViewThatFits as is, since the doubling is cheap.

## Checked, no issues
- ios-dev checklist: `@State selectedID` is private; no `@Binding`; no `@StateObject`; `ForEach` over `readings` uses stable `station.id`; each element yields one view; `.animation(_:value:)` has a value; no `AnyView`; no business logic beyond trivial selection.
- ThresholdBar's `ForEach(..., id: \.self)` over two Doubles is fine unless the two thresholds are equal, which the bundled data does not do.
- Overlay and annotation arrays are not rebuilt per frame (there is no MapKit); the GeometryReader is single, small and scoped to the map.
- Localization: all keys used here exist in Localizable.xcstrings, including the composed "Measured %@ · geomagnetic activity only", "%@, R %lld" and "Possible from R %lld". The legend deliberately stacks for long Finnish and Swedish words.
- Colour is not the only cue: marker size, fill and stroke style differ, and VoiceOver values carry the level and R. The card is combined into one element and the decorative bar is hidden.
- Dark mode: both sky palettes are dark (including the light-scheme one), so the hard-coded white foregrounds are legible. Label text white at 0.65 opacity is about 5:1 on the lightest sky. The `.screen` glow is clipped to Finland.
- Hit targets are 44 pt. The selected state is exposed via the `.isSelected` trait. `sensoryFeedback` is bound to `selectedID`.
- Missing R for an individual station is handled (dashed marker, "No recent data" value, card text). The default selection ignores nil stations.

---

# Review 1: main screen views

Scope: MainScreenView, OutlookSectionView, ChanceDetailsView, CoreLabels, FactorEffect, SkyBackground, PlacePickerView. Nothing was modified.

### [severity: medium] Sky animation keeps running behind the opaque map page and behind large sheets
File: Revontulet/MainScreen/MainScreenView.swift:36 (and SkyBackground.swift:20)
Rule/source: guide-swiftui-performance-audit (avoid continuous work that is not visible); SkyBackground's own `animated` flag exists for this case.
Problem: `SkyBackground(level: level)` always animates. The `TimelineView(.animation(minimumInterval: 1/15))` redraws about 200 gradient-filled rays (two curtains, a ray every 4 pt) into a Canvas. The Canvas then gets a 10 pt `.blur` and `.blendMode(.screen)`, and there is no `drawingGroup`. When the user pages to `StationMapPage`, its `StationMap` covers the sky, so this GPU and CPU work is never seen. It also runs while the large-detent sheets (place picker, alerts, outlook details) cover the screen. Low Power Mode is not considered either.
Suggested fix:
```swift
// MainScreenView
.background {
    SkyBackground(level: level,
                  animated: page == .chance && !isShowingAnyLargeSheet && !lowPower)
        .environment(\.colorScheme, systemColorScheme)
}
// lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, refreshed on
// .NSProcessInfoPowerStateDidChange. Rasterise the Canvas once per frame with .drawingGroup() if profiling shows it helps.
```

### [severity: medium] Forced dark look uses `.environment(\.colorScheme, .dark)` instead of `.preferredColorScheme(.dark)`
File: Revontulet/MainScreen/MainScreenView.swift:58, Revontulet/PlacePicker/PlacePickerView.swift:63
Rule/source: swiftui API reference (`preferredColorScheme` and `colorScheme`). The code itself already shows the problem: OutlookSectionView.swift:327-329 uses `preferredColorScheme(.dark)` with a comment that otherwise "the text disappears" in light mode.
Problem: The `colorScheme` environment value only changes how SwiftUI-drawn content resolves colours. It does not set the hosting controller's trait. UIKit-backed chrome (toolbar glass, page-index dots, search field and keyboard, sheet/nav-bar materials) follows the system appearance. On a light-mode device that gives dark-on-dark toolbar buttons, page dots and search text over the night sky, and a sheet that goes light at the large detent. The outlook sheet already hit this, so PlacePickerView, which has the same structure (sheet plus nav bar plus `.searchable`), is likely affected. The same applies to AlertSettingsView.
Suggested fix:
```swift
// MainScreenView: replace .environment(\.colorScheme, .dark)
.preferredColorScheme(.dark)
// PlacePickerView: same on the NavigationStack.
// SkyBackground's `colorScheme == .dark` branch becomes always-true, so the light-mode sky
// variant and the `systemColorScheme` plumbing can go. If the variant is kept, read the real
// scheme from the app root before forcing dark.
```

### [severity: medium] PlacePickerView does search and locale sorting inside `body`
File: Revontulet/PlacePicker/PlacePickerView.swift:19, 66-76
Rule/source: ios-dev Correctness Checklist, "No business logic in `body`"; performance audit, expensive work recomputed on render.
Problem: `let results = municipalities` runs `resolver.search(query, limit: 400)` on every body evaluation (every keystroke and every parent re-render). With an empty query and Swedish preferred it also sorts up to 400 items with a locale-aware `compare` that calls `displayName` twice per comparison, and it allocates `Locale(identifier: "sv_FI")` each time. The comment "once per update" does not make this acceptable. `query.trimmingCharacters(in: .whitespaces)` is also recomputed three times per render.
Suggested fix:
```swift
@State private var results: [Municipality] = []
// body uses `results`
.onChange(of: query, initial: true) { results = computeResults() }
.onChange(of: resolver == nil) { results = computeResults() }
private static let svLocale = Locale(identifier: "sv_FI")
private var isQueryEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }
// For the empty query, cache the sorted list once instead of re-sorting.
```

### [severity: medium] Date and solar math computed in `body` on every 30 s tick and model update
File: Revontulet/MainScreen/MainScreenView.swift:358-381 (`nextDarkness`), Revontulet/MainScreen/OutlookSectionView.swift:138-141 (`darkAgain`)
Rule/source: ios-dev Correctness Checklist, "No business logic in `body`"; performance audit.
Problem: `SolarPosition.nextDarkness` and `nextDarkNight` run solar-position scans from `body`. They re-run on every TimelineView tick (30 s) and every model change, although the result only changes with the place or the day. They only run in the too-light branches, which is exactly the summer case where the scans are longest (they search ahead for the next dark time).
Suggested fix: Compute them in the model, or cache them in a small `@State` keyed on `(coordinate, calendar day)`:
```swift
.task(id: DarknessKey(place: result.place.coordinate, day: Calendar.current.startOfDay(for: now))) {
    nextDark = SolarPosition.nextDarkness(...)
}
```

### [severity: low] Dynamic Type is capped at accessibility2 on the headline texts
File: Revontulet/MainScreen/MainScreenView.swift:277, 288
Rule/source: hig (Dynamic Type: support all sizes, do not cap without a strong reason); swiftui-specialist guidance.
Problem: The "Chance to see the aurora" caption and the reason line (`title2`) stop growing at AX2, while the rest of the screen keeps growing to AX5. The reason line is the most informative line next to the level, and users on AX3 to AX5 get a smaller headline reason than the body below it. The comment says the cap keeps the level larger, but the level already uses `ScaledMetric` with `minimumScaleFactor`.
Suggested fix: Remove the caps. Let the reason wrap (it already can). If the level must stay dominant, bound the level with `.dynamicTypeSize(...accessibility3)` instead of capping the supporting text.

### [severity: low] Status-state symbols are not hidden from VoiceOver
File: Revontulet/MainScreen/MainScreenView.swift:473-476
Rule/source: hig (VoiceOver: decorative images are hidden); ios-dev a11y.
Problem: The large `Image(systemName: symbol)` has no `accessibilityHidden`. VoiceOver reads auto-generated names such as "antenna radiowaves left and right slash" or "location circle" before the title. The title and message already carry the meaning.
Suggested fix: `.accessibilityHidden(true)` on the image.

### [severity: low] DataLabelStyle exposes its icon as a separate accessibility element
File: Revontulet/MainScreen/MainScreenView.swift:438-449
Rule/source: hig (VoiceOver: hide decorative icons); swiftui `LabelStyle` reference.
Problem: A custom `LabelStyle` composes `configuration.icon` and `configuration.title` into an `HStack`. The built-in styles treat the icon as decorative, but here the SF Symbol inside is a normal accessible image. The data lines (age, station, "dark enough from", warning) can therefore be read as "clock", "Measured 8 min ago", and so on.
Suggested fix: `configuration.icon.frame(width: iconWidth).foregroundStyle(.secondary).accessibilityHidden(true)`.

### [severity: low] Moon accessibility label drops the "Bright enough to hide faint aurora" line
File: Revontulet/MainScreen/ChanceDetailsView.swift:94-96
Rule/source: hig (VoiceOver: the combined label must carry the same information as the visible text).
Problem: `.accessibilityLabel(...)` on the combined row replaces the auto-combined text. When `moon.isBright`, the visible secondary line is never spoken. The effect word "Limits" is spoken, but not why.
Suggested fix: Add the sentence to the label when bright, for example `Text("\(label). \(Text("Bright enough to hide faint aurora"))")`. Alternatively drop the custom label and keep `.combine`, using `.accessibilityLabel` only on the "%" text, so "%" is spoken as "percent".

### [severity: low] SoonLine's VoiceOver label omits the "Overcast now" note
File: Revontulet/MainScreen/OutlookSectionView.swift:35-45
Rule/source: hig (VoiceOver parity with visual content).
Problem: `.accessibilityElement(children: .ignore)` plus the label `"Forecast: \(line)"` hides the visible `Text("Overcast now")`.
Suggested fix: When `isOvercastNow`, append it to the label, for example `Text("\(Text("Forecast: \(line)")). \(Text("Overcast now"))")`. Add the "%@. %@" key, which already exists.

### [severity: low] Fixed 36 x 36 icon frame in CurrentLocationRow does not scale with Dynamic Type
File: Revontulet/PlacePicker/PlacePickerView.swift:94-95
Rule/source: hig (Dynamic Type: sizes tied to text should scale); ios-dev a11y.
Problem: The symbol uses `.font(.body)` and scales, but the frame and circle background are fixed at 36 pt. At accessibility sizes the glyph overflows or crowds the circle.
Suggested fix:
```swift
@ScaledMetric(relativeTo: .body) private var badge = 36.0
.frame(width: badge, height: badge)
```

### [severity: low] Solar wind units read poorly in VoiceOver
File: Revontulet/MainScreen/ChanceDetailsView.swift:124
Rule/source: hig (VoiceOver readability of units).
Problem: "nT", "km/s" and "/cm³" are read letter by letter or as "slash c m cubed".
Suggested fix: Add a spoken variant, or use `Measurement` with `.formatted()`, which carries real unit names. Alternatively attach `.accessibilityLabel` with spelled-out units: "nanotesla", "kilometres per second", "per cubic centimetre".

### [severity: low] Dynamic localization keys are invisible to Xcode string extraction
File: Revontulet/MainScreen/CoreLabels.swift:20, 48, 136
Rule/source: swiftui-specialist guidance on localization (extraction).
Problem: `LocalizedStringResource(String.LocalizationValue(key))` is built from runtime keys (`ChanceReason`, `MoonPhase`, `OutlookReason`). Xcode never extracts them, so a missing key or typo in a translation shows up as a raw key at runtime and no build warning appears. All three are covered today (checked against Localizable.xcstrings), but this is an unguarded regression risk.
Suggested fix: Add a unit test that iterates `allCases` and asserts that each key exists in en, fi and sv in the xcstrings. Alternatively switch to literal `switch` cases, as the other enums here do.

## Checked, no issues
- Localization: every literal `Text`, `Label`, `Button` and `prompt` string in the seven files has a key in Localizable.xcstrings, with en, fi and sv values. Interpolations use format strings (`%@`, `%lld`) with positional specifiers. There is no `+` concatenation of translated text.
- Checklist: all `@State` properties are private; the `@Observable` model is passed as a plain `let`; no `@StateObject` or `ObservableObject`; no `AnyView` (`AnyLayout` in FactorTitle is fine); no `.indices` ForEach.
- ForEach: `ForEach([tonight, tomorrow], id: \.which)` is stable, and `scrollPosition(id:)` matches the ForEach id. `ForEach(1...3, id: \.self)` is a constant range. The PlacePicker ForEach uses Identifiable municipalities.
- Every `.animation` has a `value:`. `TimelineView` for the 30 s refresh and `symbolEffect(.repeat(.continuous), isActive:)` run only while active and stop on `isActive == false`.
- SkyBackground honours Reduce Motion and `animated`; the stars Canvas has no inputs and redraws only on resize.
- Liquid Glass: `.glass` and `.glassProminent` are used only for buttons, with no glass-on-glass stacking, no custom `glassEffect` and no manual toolbar backgrounds. `scrollEdgeEffectHidden` and `Button(role: .close)` are valid on iOS 26. Reduce Transparency is handled in ChanceDetailsView and ForecastFrame.
- No deprecated APIs found: `foregroundStyle`, `onChange`, `.sheet`, `NavigationStack` and `ContentUnavailableView.search` are all current.
- Hit targets: toolbar buttons are system-sized; the details toggle and the night rows have at least 44 pt of height with `contentShape`; the PlacePicker rows are List rows with a full-row `contentShape`.
- GeometryReader in the ResultView mask is used only to read the safe-area inset, not for layout.
- Contrast: white at 0.8 or `.secondary` on the near-black sky is about 4.8:1 or better even on the lighter "light-mode" sky variant. Amber, accent and green on dark are fine. State is never conveyed by colour alone (badges have a symbol and a word; meters are decorative with text).

---

# Test review 7: checklist findings

Scope: Packages/AuroraCore/Tests, RevontuletTests, RevontuletUITests, Server/Tests (all .swift files). Read-only review. Repo root: /Users/jouniuusimaa/Code/revontulet. Paths below are absolute.

Method: read every test file, then grep the trees for sleeps, `try!`, `!`, `Date()`/`.now`, `class`, `XCTAssert`, `Bundle.*`, and text-based XCUI queries. Plain `#expect(!flag)` and `#expect(predicate(x))` calls are not counted as item 3. Only comparisons against `true`, `&&`/`||` combinations and `.map {...} == true` are.

## 1. Swift Testing suites declared as `class`

- none. Every `@Suite` is a `struct`. The `class` declarations in the test trees are helpers, not suites: FakeAlertAPI, ManualClock, StubHTTPClient, NightReplayHTTPClient, TestClock, FakePushSender, FakeHeartbeat, StubConditionSource, NOAAGuardHTTPClient, GatedHTTPClient, NoLocation. The XCUI classes are `XCTestCase`, which XCTest requires.

## 2. Force unwraps (`!`) or `try!` where `try #require` should be used

- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Support/Fixtures.swift:39 — `try! Date(text, strategy: .iso8601)` in the shared `utc(_:)` helper — make `utc` `throws` and use `try utc(...)`, or keep it as the one documented fixture-only crash point.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Support/NightReplay.swift:58 — `UTCTime.parse(fields[0])!`, `Double(fields[1])!`, `Double(fields[2])!` inside the `clouds` map — make the map `try` and `throw Fixtures.FixtureError.missing(...)` on a malformed row.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Support/NightReplay.swift:69 — `UTCTime.parse(fields[0].utf8)!` in `samples(csv:stationID:)` — make the function `throws` and throw on nil.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/SelectionTests.swift:7 — `try! ReferenceData.loadStations()` in the suite's property initializer — load inside each test with `try #require` (or a `throws` helper).
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/SelectionTests.swift:14 — `stations[id]!` in `reading(_:r:)` — make the helper `throws` and use `try #require(stations[id])`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/SelectionTests.swift:51-52 — `stations["RAN"]!`, `stations["PEL"]!` — `let ran = try #require(stations["RAN"])`, same for PEL.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/NOAAParserTests.swift:150 — `try! JSONSerialization.data(withJSONObject:)` in `alerts(_:)` — make the helper `throws` and call it with `try` from the tests.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/MunicipalitySearchTests.swift:6 — `private static let resolver = try! PlaceResolver()` — create it in a `throws` helper, or build it lazily in each test with `try #require`-style setup.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/PlaceResolverTests.swift:6 — `private static let resolver = try! PlaceResolver()` — same fix as MunicipalitySearchTests:6.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertZonesTests.swift:6 — `private let zones = try! AlertZones.all()` — make `zone(_:)` and the tests `throws` and use `try AlertZones.all()`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertZonesTests.swift:9 — `zones.first { $0.id == id }!` in `zone(_:)` — return `try #require(zones.first { ... })`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertSeasonTests.swift:7 — `let kevo = try! AlertZones.all().first { $0.id == "KEV" }!` — move into each test: `let kevo = try #require(AlertZones.all().first { $0.id == "KEV" })`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertAPIModelsTests.swift:7 — `private let zones = try! AlertZones.all()` — load in the tests with `try`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/ZoneEvaluatorTests.swift:7 — `private let strong = try! RecordedNight.named("20261014")` — load per test with `try`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/ZoneEvaluatorTests.swift:8 — `private let stations = try! ReferenceData.loadStations()` — load per test with `try`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/ZoneEvaluatorTests.swift:33 — `.min { ... }!` — `let nextNearest = try #require(stations.filter { ... }.min { ... })`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/OutlookServiceTests.swift:271 — `FMIRequests.cloudForecast(zones: try! AlertZones.all())` inside `requestsAreTheSameForEveryPlace` — mark the test `async throws` and use `try AlertZones.all()`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/SoonReplayTests.swift:40 — `UTCTime.parse(f[0])!` in `samples(_:)` — make the map `throws` and throw on nil.
- /Users/jouniuusimaa/Code/revontulet/RevontuletTests/CalculatorTimingTests.swift:14 — `static let now = try! Date("2026-11-24T17:00:00Z", strategy: .iso8601)` — use a literal epoch `Date(timeIntervalSince1970: …)` (a static initializer cannot use `#require`).
- /Users/jouniuusimaa/Code/revontulet/RevontuletTests/CalculatorTimingTests.swift:51 — `runs.max()!` — make the test `throws` and use `let slowest = try #require(runs.max())`.
- /Users/jouniuusimaa/Code/revontulet/Server/Tests/AlertServerTests/Support/TestSupport.swift:66 — `try! Date(text, strategy: .iso8601)` in `utc(_:)` — same fix as Fixtures.swift:39.
- /Users/jouniuusimaa/Code/revontulet/Server/Tests/AlertServerTests/RateLimiterTests.swift:78 and :88 — `HTTPField.Name("X-Forwarded-For")!` — `let forwardedFor = try #require(HTTPField.Name("X-Forwarded-For"))` once, at the top of the test.
- /Users/jouniuusimaa/Code/revontulet/Server/Tests/AlertServerTests/TestNotificationTests.swift:31 — `HTTPField.Name("X-Forwarded-For")!` in `sendTest` — make the helper `throws` and use `try #require`.
- /Users/jouniuusimaa/Code/revontulet/Server/Tests/AlertServerTests/DeleteAndRetentionTests.swift:28 — `HTTPField.Name("X-Forwarded-For")!` in `delete` — same fix as TestNotificationTests:31.
- /Users/jouniuusimaa/Code/revontulet/Server/Tests/AlertServerTests/RegistrationRoutesTests.swift:29 — `HTTPField.Name("X-Forwarded-For")!` in `put` — same fix as TestNotificationTests:31.
- /Users/jouniuusimaa/Code/revontulet/Server/Tests/AlertServerTests/EvaluationLoopTests.swift:184 — `Int(request.token, radix: 16)! - 1` — `let index = try #require(Int(request.token, radix: 16))`, then `zones[index - 1]`.

## 3. `#expect` with a hand-made Bool, or XCTAssert in Swift Testing files

- XCTAssert in Swift Testing files: none. `import XCTest` appears only in the RevontuletUITests files.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/SelectionTests.swift:94 — `#expect(cover.distanceKm.map { abs($0 - 13.6) < 1.5 } == true)` — `let km = try #require(cover.distanceKm)` then `#expect(abs(km - 13.6) < 1.5)`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/SelectionTests.swift:112 — `#expect(cover.distanceKm.map { $0 <= 100 } == true)` — `let km = try #require(cover.distanceKm)` then `#expect(km <= 100)`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/RIndexTests.swift:69 — `#expect(r.map { abs($0 - (…)) < 1e-9 } == true)` — `let r = try #require(RIndex.compute(...))` (make the test `throws`), then `#expect(abs(r - (…)) < 1e-9)`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/FMIRequestTests.swift:73 — `#expect(first.y != nil && first.z != nil)` — two separate `#expect(first.y != nil)` and `#expect(first.z != nil)`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/ChanceCalculatorTests.swift:65 — `#expect(chance.limitingFactor != nil || chance.level == .high)` — `if chance.level != .high { #expect(chance.limitingFactor != nil) }`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/NOAAParserTests.swift:42 — `#expect(empty.bz == nil && empty.speed == nil && empty.density == nil)` — three separate `#expect` lines.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/NightsTests.swift:62 — `#expect(tonight.start == nil && tonight.relevantStart == nil && !tonight.reachesDark)` — three separate `#expect` lines.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/SolarPositionTests.swift:64 — `#expect(dark > utc(…) && dark < utc(…), "\(dark)")` — two `#expect` calls.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/SolarPositionTests.swift:73 — same pattern as :64 for `dark > … && dark < …` — two `#expect` calls.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/ZoneEvaluatorTests.swift:83-84 — `#expect(requestedURLs == [A, B] || requestedURLs == [B, A])` — `#expect(Set(http.requestedURLs) == Set([...]))`.

## 4. Async callbacks tested with sleeps or polling

- /Users/jouniuusimaa/Code/revontulet/RevontuletTests/MainScreenRefreshTests.swift:101 — `for _ in 0..<5 { await Task.yield() }` to let the alert's refresh reach the running one — replace with a deterministic signal, such as an AsyncStream the model yields when `alertOpened()` has queued behind the running refresh, and await that event.
- /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/OutlookUITests.swift:147-150 — busy-poll loop with `Date()` deadline and `RunLoop.current.run(until:)` until the title's frame is near the navigation bar — use an `XCTNSPredicateExpectation` (as `waitForLabel` does) on a predicate such as `isHittable == true`, or assert the position after the wait for the element.

## 5. Near-duplicate tests that should be one `@Test(arguments:)`

- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Outlook/OutlookCalculatorTests.swift:42-61 — `case1SomeActivity`, `case2GoodConditions`, `case3LowActivity` have the same shape (`tonight(kp: kp(X), clouds: clouds(10))`, then level and reason) — one `@Test(arguments: [(3.0, ChanceLevel.moderate, ChanceReason.someActivity), (6, .high, .goodConditions), (2, .low, .lowActivity)])`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/FMIRequestTests.swift:19-48 — `magnetometerRequest` and `cloudRequest` have an identical body and differ only in the request builder and the expected query dictionary — one parameterized test over `(URL, expected query)`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertMessageTests.swift:42-50 — `moonCaseWithAndWithoutMoonKeys` repeats the brightMoon rows of `keysPerLevelReasonAndClouds` (lines 32-40) — delete it, or fold its four assertions into the table.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertSeasonTests.swift:9-17 — `noDarknessAtKevoInLateJune` and `darknessAtKevoInNovember` differ only in the start dates and the expected Bool — one `@Test(arguments:)` over `(start, hasDarkness)`.
- Borderline: /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/NOAAParserTests.swift:69-73, :111-115, :198-202 — `brokenBodiesThrow`, `brokenKpForecastThrows` and `brokenAlertsThrow` use the same malformed fixtures and the same error, and differ only in the parser called — one parameterized test over `(parser, fixture)`.
- Borderline: /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertPolicyTests.swift:149-170 — `case12DaylightGivesNoAlert` and `case13OvercastGivesNoAlert` both assert "no level, no alert" for different chance inputs — could share one table, but the darkness computation makes this only partly the same.

## 6. Tests using the current date without an injected clock

- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/NOAAParserTests.swift:103 — `NOAAParser.kpForecast(..., fetchedAt: .now)` — pass a fixed `utc("2026-10-30T10:30:00Z")`. The asserted blocks do not depend on it, so this is not a live flake.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/NOAAParserTests.swift:114 — `fetchedAt: .now` in `brokenKpForecastThrows` — same fix as :103.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/NOAAParserTests.swift:201 — `now: .now` in `brokenAlertsThrow` — same fix; use a fixed `utc(...)`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/BsWfsParserTests.swift:102 — `fetchedAt: .now` in `cloudForecastMatchesNearestZoneWithin1KmAndDropsNaN` — pass a fixed `utc(...)`.
- /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Alerts/AlertMessageTests.swift:77 — `dataTime: .now` in `stationNameIsTheOnlyArgument` — the test does not check the time; use the fixed `utc("2026-11-03T20:00:00Z")` already used at line 10.
- /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/OutlookUITests.swift:147 — `Date().addingTimeInterval(5)` as the deadline of the polling loop in `testTomorrowOpensItsOwnDetails` — fixed by the item 4 fix (use XCTWaiter with a predicate, no wall clock).

## 7. Tests reading real network endpoints

- none. All HTTP goes through StubHTTPClient, NightReplayHTTPClient, NOAAGuardHTTPClient, or the Hummingbird in-memory test client. NOAARequestsTests and FMIRequestTests only compare URLs.

## 8. UI tests: `sleep`, text queries instead of identifiers, missing `@MainActor`

- sleep: none. The one polling loop is covered under item 4.
- Visible-text queries (should use accessibilityIdentifier; the app side needs identifiers added where none exist):
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/MainScreenOfflineUITests.swift:44 — `app.staticTexts["You're offline"]`.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/MainScreenResultUITests.swift:38-40 — `descendants.matching(label CONTAINS "Finnish Meteorological Institute (FMI), CC BY 4.0")` — give the attribution an identifier, such as `attributionText`.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/MainScreenResultUITests.swift:77 — `app.staticTexts["Outside coverage area"]` — use `app.element("outsideCoverage")`, which ManualPlaceUITests already uses.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/StationMapUITests.swift:25, :62, :67 — `app.staticTexts["Auroras in Finland now"]` — give the map title an identifier.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/StationMapUITests.swift:27 — `label CONTAINS 'Probable from R'` — give the station card an identifier.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/StationMapUITests.swift:29 and :52 — `app.buttons["Kevo"]` — give station markers identifiers such as `station-KEV`.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/StationMapUITests.swift:38 — `app.buttons["Pello"]` — same as :29.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/AlertSettingsUITests.swift:54 — `app.staticTexts["Choose a place in Finland first"]` — use `app.element("alertsNoZone")`, which is already waited on at line 53.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/AlertSettingsUITests.swift:74, :75, :76 — `app.staticTexts[...]` for the three "what is sent" sentences — check the container `alertsWhatIsSent` and its child text, or give each sentence an identifier.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/OutlookUITests.swift:118 and :128 — `app.staticTexts["This is a forecast, not a measurement"]` — give the details sheet's caption an identifier, such as `outlookDisclaimer`.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/OutlookUITests.swift:129 — `app.staticTexts["G2 (moderate)"]` — give the watch-level row an identifier.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/OutlookUITests.swift:131 — `app.staticTexts["Geomagnetic storm watch"]` — same as :129.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/OutlookUITests.swift:132 — `app.staticTexts["Helps"]` — same as :129.
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/OutlookUITests.swift:146 — `app.navigationBars["Outlook details"]` — navigation bar titles are localized; query by identifier on the sheet's root view.
- Missing class-level `@MainActor` (the xcuitest swift6-concurrency guide recommends marking the class). Each class only marks its test methods, while `setUp()` (not isolated) sets `continueAfterFailure`. Low severity:
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/ManualPlaceUITests.swift:4
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/MainScreenOfflineUITests.swift:4
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/MainScreenResultUITests.swift:4
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/StationMapUITests.swift:4
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/AlertSettingsUITests.swift:4
  - /Users/jouniuusimaa/Code/revontulet/RevontuletUITests/OutlookUITests.swift:5
  - Fix for all six: add `@MainActor` above the class declaration and drop the per-method attributes if desired. LaunchUITests.swift has no setUp and is fine as is.

## 9. Fixture loading that breaks on Linux (Bundle.main, missing Bundle.module resource)

- none. Packages/AuroraCore/Package.swift declares `resources: [.copy("Fixtures")]` on AuroraCoreTests, and Support/Fixtures.swift and MagnetometerFixtures.swift use `Bundle.module`. Server/Package.swift declares no test resources, and the Server tests use no Bundle API. Server/Tests/AlertServerTests/Support/NightReplay.swift:25-28 reads AuroraCore's fixtures through `#filePath`, which works on Linux but depends on the repo layout.
- Not a Linux issue: RevontuletTests/AlertStringsTests.swift:12 uses `Bundle.main`. The RevontuletTests bundle is app-hosted (`@testable import Revontulet`), and it does not run on Linux.

## 10. Shared mutable static state between tests

- /Users/jouniuusimaa/Code/revontulet/RevontuletTests/MainScreenRefreshTests.swift:59-60 — `UserDefaults(suiteName: "MainScreenRefreshTests")` with `removePersistentDomain` in `model(_:)`, shared by `normalRefreshReusesRecentData`, `openingAnAlertFetchesNewData` and `alertOpenedDuringANormalRefreshFetchesAfterIt`. The suite is `@MainActor`, so these tests interleave at their await points and can share the domain. Fix: use a unique suite name per test (for example `"MainScreenRefreshTests.\(UUID())"`), as `mapFillsWithoutAPlace` already does with its own name at line 128, and remove it at the end.
- Borderline: /Users/jouniuusimaa/Code/revontulet/Packages/AuroraCore/Tests/AuroraCoreTests/Support/NightReplay.swift:24 — `private static let cache = Mutex<[String: RecordedNight]>([:])`, a process-wide cache. It is Mutex-protected and the values are immutable, so it is safe, but the lookup and the store are separate locks, so two parallel tests can load the same night twice. Harmless; keep, or document.
- Other static state checked and fine: all other `static let` values are immutable (tokens, fixtures lists, parsed reference data, `SyntheticNight` list). There are no `static var` declarations in the test trees.
