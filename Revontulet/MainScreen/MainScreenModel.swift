import AuroraCore
import Foundation
import Observation

/// Drives the main screen (contracts/main-screen-states.md). Core work runs off the main actor:
/// `AuroraService` is an actor and place resolution runs in a detached task.
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

    private(set) var state: State = .determiningLocation
    private(set) var isRefreshing = false

    private let service: AuroraService
    private let location: any LocationProviding
    private let resolver: Task<PlaceResolver?, Never>
    private let now: @Sendable () -> Date

    init(
        service: AuroraService,
        location: any LocationProviding,
        loadResolver: @escaping @Sendable () throws -> PlaceResolver = { try PlaceResolver() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.location = location
        // Loading the municipality boundaries takes a moment; start it right away, off the main actor.
        resolver = Task.detached(priority: .userInitiated) { try? loadResolver() }
        self.now = now
    }

    var hasResult: Bool {
        if case .result = state { true } else { false }
    }

    /// Locates the user and computes a fresh result. A valid result is never replaced by an
    /// empty state when a later step fails.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if !hasResult { state = .determiningLocation }
        let position: (latitude: Double, longitude: Double)
        switch await location.currentLocation() {
        case .location(let latitude, let longitude):
            position = (latitude, longitude)
        case .denied:
            state = .locationDenied
            return
        case .unavailable:
            if !hasResult { state = .noData }
            return
        }

        guard let resolver = await resolver.value else {
            if !hasResult { state = .noData }
            return
        }
        let resolution = await Task.detached {
            resolver.resolve(latitude: position.latitude, longitude: position.longitude)
        }.value
        guard case .inside(let municipality) = resolution else {
            state = .outsideCoverage
            return
        }

        let place = Place(
            coordinate: Coordinate(latitude: position.latitude, longitude: position.longitude),
            municipalityCode: municipality.code, source: .currentLocation)
        if !hasResult { state = .loading }
        do {
            let result = try await service.refresh(for: place, at: now(), force: false)
            state = .result(result, placeName: municipality.displayName(preferSwedish: Self.prefersSwedish))
        } catch {
            if !hasResult { state = .noData }
        }
    }

    /// Swedish municipality names are shown when the app runs in Swedish.
    static var prefersSwedish: Bool {
        Bundle.main.preferredLocalizations.first == "sv"
    }
}
