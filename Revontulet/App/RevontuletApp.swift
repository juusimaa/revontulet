import AuroraCore
import SwiftUI

@main
struct RevontuletApp: App {
    @State private var model = AppDependencies.makeMainScreenModel()

    var body: some Scene {
        WindowGroup {
            MainScreenView(model: model)
        }
    }
}

/// Builds the app's object graph. UI tests swap in stubs with launch arguments:
/// `-uiTestStubs` (synthetic FMI responses), `-uiTestOffline` (every request fails),
/// `-uiTestResetCache` (start without a cached result or chosen municipality),
/// `-uiTestLocation lat,lon` (fixed position) and `-uiTestLocationDenied` (no location access).
@MainActor
enum AppDependencies {
    static func makeMainScreenModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> MainScreenModel {
        let http: any HTTPClient =
            if arguments.contains("-uiTestOffline") { OfflineHTTPClient() }
            else if arguments.contains("-uiTestStubs") { UITestHTTPClient() }
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
            service: service, location: locationProvider(arguments: arguments), placeStore: placeStore)
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
