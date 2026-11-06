import AuroraCore
import Foundation
import Synchronization
import Testing
@testable import Revontulet

/// Opening an alert must show newly fetched data, even while a normal refresh is running (issue #10).
@Suite("Main screen refresh")
@MainActor
struct MainScreenRefreshTests {
    /// Serves the UI-test stubs and counts magnetometer requests. While `isHolding`, the first
    /// magnetometer request waits until `release()`, so a refresh can be kept in flight.
    final class GatedHTTPClient: HTTPClient {
        private let stubs = UITestHTTPClient()
        private let state = Mutex<(count: Int, isHolding: Bool, waiter: CheckedContinuation<Void, Never>?)>(
            (0, false, nil))
        let entered: AsyncStream<Void>
        private let enteredContinuation: AsyncStream<Void>.Continuation

        init() {
            (entered, enteredContinuation) = AsyncStream.makeStream()
        }

        var magnetometerRequests: Int { state.withLock { $0.count } }

        func hold() { state.withLock { $0.isHolding = true } }

        func release() {
            let waiter = state.withLock { state in
                state.isHolding = false
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume()
        }

        func get(_ url: URL) async throws -> (Data, Int) {
            if url.absoluteString.contains("magnetometer") {
                let isHeld = state.withLock { state in
                    state.count += 1
                    return state.isHolding
                }
                if isHeld {
                    await withCheckedContinuation { continuation in
                        state.withLock { $0.waiter = continuation }
                        enteredContinuation.yield()
                    }
                }
            }
            return try await stubs.get(url)
        }
    }

    final class NoLocation: LocationProviding {
        func currentLocation() async -> LocationOutcome { .unavailable }
    }

    private func model(_ http: GatedHTTPClient) throws -> MainScreenModel {
        let defaults = try #require(UserDefaults(suiteName: "MainScreenRefreshTests"))
        defaults.removePersistentDomain(forName: "MainScreenRefreshTests")
        let store = PlaceSelectionStore(defaults: defaults)
        // Rovaniemi, chosen by hand, so no location fix is needed.
        store.selection = .municipality(code: "698")
        return MainScreenModel(
            service: try AuroraService(http: http, cache: InMemoryResultCache()),
            location: NoLocation(), placeStore: store)
    }

    @Test func normalRefreshReusesRecentData() async throws {
        let http = GatedHTTPClient()
        let model = try model(http)

        await model.refresh()
        await model.refresh()

        #expect(model.hasResult)
        #expect(http.magnetometerRequests == 1)
    }

    @Test func openingAnAlertFetchesNewData() async throws {
        let http = GatedHTTPClient()
        let model = try model(http)

        await model.refresh()
        await model.alertOpened()

        #expect(http.magnetometerRequests == 2)
    }

    /// The app comes to the foreground and starts a normal refresh just as the alert is opened.
    @Test func alertOpenedDuringANormalRefreshFetchesAfterIt() async throws {
        let http = GatedHTTPClient()
        let model = try model(http)
        http.hold()

        let normal = Task { await model.refresh() }
        var entered = http.entered.makeAsyncIterator()
        await entered.next()
        let alert = Task { await model.alertOpened() }
        // Let the alert's refresh reach the running one before it ends.
        for _ in 0..<5 { await Task.yield() }
        http.release()
        await normal.value
        await alert.value

        #expect(http.magnetometerRequests == 2)
        #expect(model.hasResult)
        #expect(!model.isRefreshing)
    }
}
