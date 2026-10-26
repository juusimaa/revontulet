import AuroraCore
import Foundation
import Observation

/// Drives the main screen (contracts/main-screen-states.md). Core work runs off the main actor:
/// `AuroraService` is an actor and place resolution runs in a detached task.
///
/// The cached result is shown before any location or network work; while the app is active the
/// result is refreshed every 5 minutes, and the service fetches only the data that is due.
/// A municipality chosen by the user replaces the device's position until the user switches back.
@Observable
@MainActor
final class MainScreenModel {
    enum State: Equatable {
        /// No result yet; data is being fetched.
        case loading
        /// Waiting for the first location fix.
        case determiningLocation
        case result(AuroraResult, placeName: String)
        /// No result could be computed (no data, or the fetch failed with nothing to show).
        case noData
        case locationDenied
        case outsideCoverage
    }

    /// How current a shown result is.
    enum Freshness: Equatable {
        case current
        /// The measurement is more than 30 minutes old (FR-006).
        case outdated
        /// The last refresh could not fetch data; the result shown is the last known one.
        case offline
    }

    static let foregroundRefreshInterval: Duration = .seconds(5 * 60)
    /// Manual refreshes closer together than this do not force new fetches.
    static let manualRefreshDebounce: TimeInterval = 30

    private(set) var state: State = .determiningLocation
    private(set) var isRefreshing = false
    /// true when the last refresh failed to fetch data from FMI.
    private(set) var isOffline = false
    private(set) var selection: PlaceSelection
    /// Counts refreshes asked for by the user that ended with a fresh result.
    private(set) var userRefreshesCompleted = 0
    /// The bundled municipalities, once loaded; the place picker searches them.
    private(set) var placeResolver: PlaceResolver?

    private let service: AuroraService
    private let location: any LocationProviding
    private let placeStore: PlaceSelectionStore
    private let resolver: Task<PlaceResolver?, Never>
    /// The current time; UI tests can shift it.
    let now: @Sendable () -> Date
    /// Told about every place a result is computed for, so the alert zone follows it (FR-004).
    private let onPlaceResolved: @MainActor (Place) -> Void
    private var lastForcedRefresh: Date?
    private var refreshTask: Task<Void, Never>?

    init(
        service: AuroraService,
        location: any LocationProviding,
        placeStore: PlaceSelectionStore = PlaceSelectionStore(),
        loadResolver: @escaping @Sendable () throws -> PlaceResolver = { try PlaceResolver() },
        now: @escaping @Sendable () -> Date = { Date() },
        onPlaceResolved: @escaping @MainActor (Place) -> Void = { _ in }
    ) {
        self.service = service
        self.onPlaceResolved = onPlaceResolved
        self.location = location
        self.placeStore = placeStore
        selection = placeStore.selection
        // Loading the municipality boundaries takes a moment; start it right away, off the main actor.
        let resolver = Task.detached(priority: .userInitiated) { try? loadResolver() }
        self.resolver = resolver
        self.now = now
        Task { [weak self] in self?.placeResolver = await resolver.value }
    }

    var hasResult: Bool {
        if case .result = state { true } else { false }
    }

    func freshness(of result: AuroraResult, at date: Date) -> Freshness {
        if isOffline { .offline } else if result.isOutdated(now: date) { .outdated } else { .current }
    }

    /// Runs while the scene is active: shows the cached result, refreshes, then refreshes every
    /// 5 minutes until the task is cancelled (the app leaves the foreground).
    func runWhileActive() async {
        await showCachedResult()
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.foregroundRefreshInterval)
            } catch {
                return
            }
            await refresh()
        }
    }

    /// Shows the last stored result, if nothing is shown yet. No location or network work (FR-008).
    func showCachedResult() async {
        guard !hasResult, let cached = await service.cachedResult(), matchesSelection(cached.place) else { return }
        let name = await resolver.value?.municipality(code: cached.place.municipalityCode)?
            .displayName(preferSwedish: Self.prefersSwedish)
        guard !hasResult, matchesSelection(cached.place), let name else { return }
        state = .result(cached, placeName: name)
    }

    /// Switches to another place, remembers it across launches and computes its result. Data
    /// fetched in the last few minutes is reused, so a switch usually needs no network.
    func choose(_ newSelection: PlaceSelection) async {
        guard newSelection != selection else { return }
        selection = newSelection
        placeStore.selection = newSelection
        // The result shown is for the previous place.
        if case .result(let result, _) = state, !matchesSelection(result.place) {
            state = newSelection == .currentLocation ? .determiningLocation : .loading
        }
        // A refresh for the previous place, e.g. one waiting for a location fix, is abandoned.
        refreshTask?.cancel()
        refreshTask = nil
        await refresh()
    }

    private func matchesSelection(_ place: Place) -> Bool {
        switch selection {
        case .currentLocation: place.source == .currentLocation
        case .municipality(let code): place.source == .manual && place.municipalityCode == code
        }
    }

    /// Refresh asked for by the user: forces new fetches, at most once per 30 seconds. A refresh
    /// within that time still re-locates and fetches whatever is due, so the user sees an outcome.
    func userRefresh() async {
        let date = now()
        let force = lastForcedRefresh.map { date.timeIntervalSince($0) >= Self.manualRefreshDebounce } ?? true
        if force { lastForcedRefresh = date }
        await refresh(force: force)
        if hasResult, !isOffline { userRefreshesCompleted += 1 }
    }

    /// Locates the user (or takes the chosen municipality) and computes a fresh result. A valid
    /// result is never replaced by an empty state when a later step fails.
    /// A refresh asked for while one is running waits for that one instead of starting another.
    func refresh(force: Bool = false) async {
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { await refreshOnce(force: force) }
        refreshTask = task
        isRefreshing = true
        await task.value
        // A place change may have replaced this refresh with a new one.
        if refreshTask == task {
            refreshTask = nil
            isRefreshing = false
        }
    }

    private func refreshOnce(force: Bool) async {
        let selection = self.selection
        // The user may pick another place while this refresh waits; its outcome is then dropped.
        var isStale: Bool { Task.isCancelled || selection != self.selection }

        guard let resolver = await resolver.value else {
            if !hasResult { state = .noData }
            return
        }
        let place: Place
        let municipality: Municipality
        if case .municipality(let code) = selection, let chosen = resolver.municipality(code: code) {
            municipality = chosen
            place = Place(manual: chosen)
        } else {
            if !hasResult { state = .determiningLocation }
            let position: (latitude: Double, longitude: Double)
            let outcome = await location.currentLocation()
            guard !isStale else { return }
            switch outcome {
            case .location(let latitude, let longitude):
                position = (latitude, longitude)
            case .denied:
                state = .locationDenied
                return
            case .unavailable:
                if !hasResult { state = .noData }
                return
            }
            let resolution = await Task.detached {
                resolver.resolve(latitude: position.latitude, longitude: position.longitude)
            }.value
            guard !isStale else { return }
            guard case .inside(let found) = resolution else {
                state = .outsideCoverage
                return
            }
            municipality = found
            place = Place(
                coordinate: Coordinate(latitude: position.latitude, longitude: position.longitude),
                municipalityCode: found.code, source: .currentLocation)
        }

        if !hasResult { state = .loading }
        do {
            let result = try await service.refresh(for: place, at: now(), force: force)
            guard !isStale else { return }
            isOffline = false
            state = .result(result, placeName: municipality.displayName(preferSwedish: Self.prefersSwedish))
            onPlaceResolved(place)
        } catch AuroraServiceError.offline {
            guard !isStale else { return }
            isOffline = true
            if !hasResult { state = .noData }
        } catch {
            guard !isStale else { return }
            isOffline = false
            if !hasResult { state = .noData }
        }
    }

    /// Swedish municipality names are shown when the app runs in Swedish.
    static var prefersSwedish: Bool {
        Bundle.main.preferredLocalizations.first == "sv"
    }
}
