import AuroraCore
import SwiftUI

@main
struct RevontuletApp: App {
    @UIApplicationDelegateAdaptor private var pushRegistration: PushRegistration
    @State private var model = AppDependencies.makeMainScreenModel()
    @State private var alerts = AppDependencies.alertSettings

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainScreenView(model: model, alerts: alerts)
                .task { await alerts.load() }
                // Sends pending alert changes on every foreground and retries while open; no
                // background work (research R13).
                .task(id: scenePhase) {
                    if scenePhase == .active { await alerts.runWhileActive() }
                }
        }
    }
}

/// Builds the app's object graph. UI tests swap in stubs with launch arguments:
/// `-uiTestStubs` (synthetic FMI responses), `-uiTestStrongActivity` (stubs with high activity),
/// `-uiTestTime <ISO 8601 date>` (the clock starts at that time), `-uiTestOffline` (every request fails),
/// `-uiTestResetCache` (start without a cached result or chosen municipality),
/// `-uiTestLocation lat,lon` (fixed position), `-uiTestLocationDenied` (no location access) and
/// `-uiTestAlertsStub` (in-memory alert service, notifications allowed, fixed push token) and
/// `-uiTestAlertsUnreachable` (with the stub, every alert service call fails).
@MainActor
enum AppDependencies {
    /// Shared with the app delegate, which receives the push token.
    static let alertSettings = makeAlertSettingsModel()

    static func makeAlertSettingsModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> AlertSettingsModel {
        if arguments.contains("-uiTestAlertsStub") {
            return AlertSettingsModel(
                sync: AlertSync(api: UITestAlertAPI(unreachable: arguments.contains("-uiTestAlertsUnreachable")),
                                store: InMemoryAlertSyncStore()),
                permission: GrantedNotificationPermission(), push: UITestPushRegistration())
        }
        return AlertSettingsModel(
            sync: AlertSync(api: URLSessionAlertAPI(baseURL: AlertConfiguration.baseURL), store: UserDefaultsAlertSyncStore()),
            permission: NotificationPermission(), push: RemoteNotificationRegistration())
    }

    static func makeMainScreenModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> MainScreenModel {
        let http: any HTTPClient =
            if arguments.contains("-uiTestOffline") { OfflineHTTPClient() }
            else if arguments.contains("-uiTestStubs") {
                UITestHTTPClient(strongActivity: arguments.contains("-uiTestStrongActivity"))
            }
            else { URLSessionHTTPClient() }
        let cache = FileResultCache()
        let placeStore = PlaceSelectionStore()
        if arguments.contains("-uiTestResetCache") {
            cache.clear()
            placeStore.clear()
        }
        // The bundled station table is part of the app; failing to load it is a build error.
        let service = try! AuroraService(http: http, cache: cache)
        return MainScreenModel(
            service: service, location: locationProvider(arguments: arguments), placeStore: placeStore,
            now: clock(arguments: arguments),
            onPlaceResolved: { place in Task { await alertSettings.placeResolved(place) } })
    }

    /// The real clock, or one that starts at `-uiTestTime` and runs at normal speed from there.
    private static func clock(arguments: [String]) -> @Sendable () -> Date {
        guard let index = arguments.firstIndex(of: "-uiTestTime"), index + 1 < arguments.count,
              let start = try? Date(arguments[index + 1], strategy: .iso8601)
        else { return { Date() } }
        let offset = start.timeIntervalSinceNow
        return { Date().addingTimeInterval(offset) }
    }

    private static func locationProvider(arguments: [String]) -> any LocationProviding {
        if arguments.contains("-uiTestLocationDenied") { return FixedLocationProvider(.denied) }
        if let index = arguments.firstIndex(of: "-uiTestLocation"), index + 1 < arguments.count {
            let parts = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                return FixedLocationProvider(.location(latitude: parts[0], longitude: parts[1]))
            }
        }
        return LocationProvider()
    }
}
