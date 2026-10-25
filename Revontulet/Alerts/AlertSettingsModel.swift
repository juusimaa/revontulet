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

    /// How often a pending change is retried while the app is open; `AlertSync` applies the backoff.
    static let retryTick: Duration = .seconds(15)

    private(set) var syncState = AlertSyncState()
    private(set) var permission: NotificationPermissionStatus = .notDetermined
    private(set) var isAskingPermission = false
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

    /// The zone's station name, e.g. "Oulujärvi".
    var zoneName: String? {
        syncState.zone.flatMap { id in zones.first { $0.id == id }?.station.name }
    }

    /// Loads the stored state; call once at launch.
    func load() async {
        await refresh()
        threshold = syncState.threshold
    }

    /// Runs while the app is in the foreground: re-reads the permission, sends what is pending
    /// (re-confirming once a day) and retries with backoff until cancelled.
    func runWhileActive() async {
        permission = await permissionProvider.status()
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
        await sync.setDesired(.disabled)
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
