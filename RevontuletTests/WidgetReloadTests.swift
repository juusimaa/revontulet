import AuroraCore
import Foundation
import Testing
@testable import Revontulet

/// The app tells the widgets about new data, but not about an identical result (research R11).
@Suite("Widget reload")
@MainActor
struct WidgetReloadTests {
    final class NoLocation: LocationProviding {
        func currentLocation() async -> LocationOutcome { .unavailable }
    }

    /// Serves the UI-test stubs, then optionally a changed measurement time.
    final class ShiftingHTTPClient: HTTPClient {
        private let stubs = UITestHTTPClient()
        func get(_ url: URL) async throws -> (Data, Int) { try await stubs.get(url) }
    }

    private final class Counter { var count = 0 }

    private func make(cache: InMemoryResultCache = InMemoryResultCache())
        throws -> (MainScreenModel, Counter, PlaceSelectionStore)
    {
        let suite = "WidgetReloadTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = PlaceSelectionStore(defaults: defaults)
        store.selection = .municipality(code: "698")
        let counter = Counter()
        let model = MainScreenModel(
            service: try AuroraService(http: ShiftingHTTPClient(), cache: cache),
            location: NoLocation(), placeStore: store, widgetReload: { counter.count += 1 })
        return (model, counter, store)
    }

    @Test func newResultReloadsOnce() async throws {
        let (model, counter, _) = try make()
        await model.refresh()
        #expect(model.hasResult)
        #expect(counter.count == 1)
    }

    @Test func identicalResultDoesNotReload() async throws {
        let (model, counter, _) = try make()
        await model.refresh()
        await model.refresh(force: true)
        #expect(counter.count == 1)
    }

    @Test func changedMeasuredAtOrLevelReloads() async throws {
        let (model, counter, _) = try make()
        await model.refresh()
        guard case .result(let first, _) = model.state else { Issue.record("no result"); return }
        #expect(counter.count == 1)

        // Same result with another measured time, then another level, through the model's own rule.
        let later = StationReading(
            station: first.reading.station, r: first.reading.r,
            measuredAt: first.reading.measuredAt.addingTimeInterval(600), activity: first.reading.activity)
        let shifted = AuroraResult(
            place: first.place, chance: first.chance, reading: later,
            distanceToStationKm: first.distanceToStationKm, usedMoreDistantStation: first.usedMoreDistantStation,
            darkness: first.darkness, clouds: first.clouds, moon: first.moon, computedAt: first.computedAt)
        #expect(!MainScreenModel.isSameForWidgets(first, shifted))

        let otherLevel = Chance(
            level: first.chance.level == .none ? .high : .none, limitingFactor: first.chance.limitingFactor,
            cloudsIncluded: first.chance.cloudsIncluded)
        let changed = AuroraResult(
            place: first.place, chance: otherLevel, reading: first.reading,
            distanceToStationKm: first.distanceToStationKm, usedMoreDistantStation: first.usedMoreDistantStation,
            darkness: first.darkness, clouds: first.clouds, moon: first.moon, computedAt: first.computedAt)
        #expect(!MainScreenModel.isSameForWidgets(first, changed))
        #expect(MainScreenModel.isSameForWidgets(first, first))
    }

    @Test func choosingAnotherPlaceReloadsOnce() async throws {
        let (model, counter, _) = try make()
        await model.refresh()
        let before = counter.count
        await model.choose(.municipality(code: "091"))
        #expect(counter.count == before + 1)
    }

    @Test func choosingTheSamePlaceDoesNotReload() async throws {
        let (model, counter, _) = try make()
        await model.refresh()
        let before = counter.count
        await model.choose(.municipality(code: "698"))
        #expect(counter.count == before)
    }
}
