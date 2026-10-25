import AuroraCore
import Foundation
import Observation

/// Drives the alert settings and the bell on the main screen (contracts/alert-settings-states.md).
///
/// Nothing is sent before the user turns alerts on (FR-002). Service failures never surface as
/// errors: the settings show "Waiting to confirm" and `AlertSync` retries (FR-005, FR-007).
@Observable
@MainActor
final class AlertSettingsModel {
    enum Phase: Equatable {
        /// No place in Finland resolved yet, so there is no zone to register.
        case noZone
        case off
        /// The system notification prompt is showing.
        case askingPermission
        /// Notifications are not allowed for the app.
        case permissionDenied
        case on(confirming: Bool)
    }

    /// "Send test" and its outcome (US3).
    enum TestStatus: Hashable {
        case idle
        case sending
        case sent
        /// Rate limited (429): "Try again at 21:40".
        case tryAgain(at: Date)
        /// Unreachable, or the registration was missing and has been re-sent.
        case failed
    }

    /// How often a pending change is retried while the app is open; `AlertSync` applies the backoff.
    static let retryTick: Duration = .seconds(15)
    static let privacyPolicyURL = URL(string: "https://github.com/juusimaa/revontulet/blob/main/docs/privacy.md")!

    private(set) var syncState = AlertSyncState()
    private(set) var permission: NotificationPermissionStatus = .notDetermined
    private(set) var isAskingPermission = false
    private(set) var testStatus: TestStatus = .idle
    /// The threshold shown in the picker; while on, changing it updates the registration.
    var threshold: AlertThreshold = .default

    private let sync: AlertSync
    private let permissionProvider: any NotificationPermissionProviding
    private let push: any PushRegistering
    private let zones: [AlertZone]
    private let now: @Sendable () -> Date

    init(sync: AlertSync, permission: any NotificationPermissionProviding, push: any PushRegistering,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.sync = sync
        permissionProvider = permission
        self.push = push
        // The bundled station table is part of the app; failing to load it is a build error.
        zones = try! AlertZones.all()
        self.now = now
    }

    var phase: Phase {
        if isAskingPermission { return .askingPermission }
        if syncState.isOn { return .on(confirming: syncState.isPending) }
        if permission == .denied, syncState.zone != nil { return .permissionDenied }
        return syncState.zone == nil ? .noZone : .off
    }

    var isOn: Bool { syncState.isOn }

    /// Alerts have never been on: explain what is sent before the first time (FR-002).
    var isFirstTime: Bool { !syncState.hasEverEnabled }

    /// Turned off, but the service has not confirmed the deletion yet ("Removing…").
    var isRemoving: Bool { !syncState.isOn && syncState.isPending }

    /// The zone's station name, e.g. "Oulujärvi".
    var zoneName: String? {
        syncState.zone.flatMap { id in zones.first { $0.id == id }?.station.name }
    }

    /// When the service last confirmed the registration ("Confirmed <relative date>").
    var confirmedAt: Date? { syncState.confirmedAt }

    /// Whether it gets dark enough at the zone within the next 24 hours; false shows the
    /// "On, no dark nights" note.
    var hasDarkNights: Bool {
        guard let zone = syncState.zone.flatMap({ id in zones.first { $0.id == id } }) else { return true }
        return AlertSeason.hasDarknessWithin24h(zone: zone, from: now())
    }

    /// Loads the stored state; call once at launch.
    func load() async {
        await refresh()
        threshold = syncState.threshold
    }

    /// Runs while the app is in the foreground: re-reads the permission, sends what is pending
    /// (re-confirming once a day) and retries with backoff until cancelled.
    func runWhileActive() async {
        await checkPermission()
        await sync.sync(now: now())
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.retryTick)
            } catch {
                return
            }
            await sync.retryIfDue(now: now())
            await refresh()
        }
    }

    /// Notifications turned off in iOS Settings while alerts are on: delete the registration and
    /// show alerts off with "Notifications are off for Revontulet" (research R7). Turning
    /// notifications back on does not turn alerts back on.
    func checkPermission() async {
        permission = await permissionProvider.status()
        if permission == .denied { await sync.permissionRevoked() }
        await refresh()
    }

    func turnOn() async {
        guard let zone = syncState.zone else { return }
        isAskingPermission = true
        let allowed = await permissionProvider.request()
        permission = await permissionProvider.status()
        isAskingPermission = false
        guard allowed else { return }
        push.register()
        await sync.setDesired(.enabled(zone: zone, threshold: threshold))
        await refresh()
    }

    func turnOff() async {
        testStatus = .idle
        await sync.setDesired(.disabled)
        await refresh()
    }

    func sendTest() async {
        guard testStatus != .sending else { return }
        testStatus = .sending
        switch await sync.sendTest() {
        case .sent: testStatus = .sent
        case .rateLimited(let until): testStatus = .tryAgain(at: until)
        case .notRegistered, .failed: testStatus = .failed
        }
        await refresh()
    }

    func thresholdChanged() async {
        guard case .enabled(let zone, let current) = syncState.desired, current != threshold else { return }
        await sync.setDesired(.enabled(zone: zone, threshold: threshold))
        await refresh()
    }

    /// The main screen computed a result for a place in Finland (FR-004): updates the zone only
    /// when it changes. Uses the place the main screen already has; no extra location requests.
    func placeResolved(_ place: Place) async {
        let zone = AlertZones.zone(for: place.coordinate, previous: syncState.zone, in: zones)
        guard zone.id != syncState.zone else { return }
        await sync.zoneChanged(to: zone.id)
        await refresh()
    }

    func tokenReceived(_ token: String) async {
        await sync.tokenChanged(token)
        await refresh()
    }

    /// Asks APNs for the token again on launch while alerts are on.
    func registerForPushIfOn() async {
        await refresh()
        if syncState.isOn { push.register() }
    }

    private func refresh() async {
        syncState = await sync.state
    }
}
