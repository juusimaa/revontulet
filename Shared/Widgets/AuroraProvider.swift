import AuroraCore
import Foundation
import WidgetKit

/// Builds the widget entries from what the app cached in the App Group. Cache only for now: it never
/// fetches. Lives in `Shared/` so the app's unit tests can reach it.
struct AuroraProvider: TimelineProvider {
    typealias Entry = AuroraEntry

    /// How long to wait before asking again when there is no place to show (FR-021).
    static let noPlaceDelay: TimeInterval = 60 * 60
    /// How long a refresh may fetch before the widget falls back to the cache.
    static let fetchBudget: TimeInterval = 8

    let loadResult: @Sendable () async -> AuroraResult?
    let loadOutlook: @Sendable () async -> OutlookSnapshot?
    let fetchResult: @Sendable (Place, Date) async -> AuroraResult?
    let fetchOutlook: @Sendable (Place, Date) async -> OutlookSnapshot?
    let cancelFetch: @Sendable () async -> Void
    let fetchBudget: TimeInterval
    let readSelection: @Sendable () -> PlaceSelection
    let now: @Sendable () -> Date
    let prefersSwedish: Bool

    init(
        loadResult: @escaping @Sendable () async -> AuroraResult? = { await FileResultCache().load() },
        loadOutlook: @escaping @Sendable () async -> OutlookSnapshot? = { await FileOutlookCache().load() },
        fetchResult: @escaping @Sendable (Place, Date) async -> AuroraResult? = { await WidgetDataLoader.shared.result(for: $0, at: $1) },
        fetchOutlook: @escaping @Sendable (Place, Date) async -> OutlookSnapshot? = { await WidgetDataLoader.shared.outlook(for: $0, at: $1) },
        cancelFetch: @escaping @Sendable () async -> Void = AuroraProvider.cancelSharedFetch,
        fetchBudget: TimeInterval = AuroraProvider.fetchBudget,
        readSelection: @escaping @Sendable () -> PlaceSelection = { PlaceSelectionStore().selection },
        now: @escaping @Sendable () -> Date = { Date() },
        prefersSwedish: Bool = Bundle.main.preferredLocalizations.first == "sv"
    ) {
        self.loadResult = loadResult
        self.loadOutlook = loadOutlook
        self.fetchResult = fetchResult
        self.fetchOutlook = fetchOutlook
        self.cancelFetch = cancelFetch
        self.fetchBudget = fetchBudget
        self.readSelection = readSelection
        self.now = now
        self.prefersSwedish = prefersSwedish
    }

    /// Not an inline default-argument closure: Swift 6.4 skips actor-isolation checks there and wrongly warns
    /// that the needed `await` is unnecessary.
    private static func cancelSharedFetch() async { await WidgetDataLoader.shared.cancel() }

    /// The redacted loading layout: the sample, which WidgetKit draws redacted.
    func placeholder(in context: Context) -> AuroraEntry {
        .sample(at: now())
    }

    /// The gallery shows the marked sample; otherwise the current entry.
    func getSnapshot(in context: Context, completion: @escaping @Sendable (AuroraEntry) -> Void) {
        if context.isPreview {
            completion(.sample(at: now()))
            return
        }
        let family = context.family
        Task { completion(await build(family: family).entries[0]) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AuroraEntry>) -> Void) {
        let family = context.family
        Task {
            let built = await build(family: family)
            completion(Timeline(entries: built.entries, policy: .after(built.nextReload)))
        }
    }

    /// The entries from now on (the current one, then the moment it turns stale if that is still ahead)
    /// and when to reload next (contracts/widget-refresh.md, steps 1-2 and 5-7).
    func build(family: WidgetFamily) async -> (entries: [AuroraEntry], nextReload: Date) {
        let now = now()
        let selection = readSelection()
        let stored = await loadResult()

        let code: String
        let coordinate: Coordinate
        let place: Place
        switch selection {
        case .municipality(let selectedCode):
            guard let name = try? MunicipalityNames.lookup(code: selectedCode) else {
                return noPlace(now)
            }
            code = name.code
            coordinate = name.representativePoint
            place = Place(coordinate: coordinate, municipalityCode: code, source: .manual)
        case .currentLocation:
            // Outside coverage the app never stores a result, so this is also the out-of-coverage case.
            guard let cached = stored else { return noPlace(now) }
            code = cached.place.municipalityCode
            coordinate = cached.place.coordinate
            place = cached.place
        }

        let placeName = (try? MunicipalityNames.lookup(code: code))?
            .displayName(preferSwedish: prefersSwedish) ?? ""
        let nextReload = WidgetRefreshPolicy.nextReload(after: now, at: coordinate)

        // Fetch if due; on timeout or failure the cache stands (contracts/widget-refresh.md). One budget for both fetches.
        let deadline = ContinuousClock.now + .seconds(fetchBudget)
        let cached = await raced(until: deadline, fallback: stored) { await fetchResult(place, now) }

        // The widget never shows another place's result, nor a level without a valid R value.
        guard let cached, cached.place.municipalityCode == code, cached.reading.r != nil else {
            return ([AuroraEntry(date: now, state: .noData, placeName: placeName)], nextReload)
        }
        // Only the medium widget shows the outlook.
        let outlook: OutlookSnapshot? = family == .systemMedium
            ? await raced(until: deadline, fallback: await loadOutlook()) { await fetchOutlook(place, now) }
            : nil
        let snapshot = WidgetSnapshot.make(result: cached, outlook: outlook, now: now)
        var entries = [AuroraEntry(date: now, state: snapshot.isStale ? .stale(snapshot) : .current(snapshot),
                                   placeName: placeName)]
        // A second entry turns the widget stale without a reload (data-model.md, transitions).
        let staleAt = WidgetRefreshPolicy.staleMoment(measuredAt: cached.reading.measuredAt)
        if staleAt > now {
            var stale = WidgetSnapshot.make(result: cached, outlook: outlook, now: staleAt)
            stale.isStale = true // isOutdated is strict, so it is still false at exactly this moment
            entries.append(AuroraEntry(date: staleAt, state: .stale(stale), placeName: placeName))
        }
        return (entries, nextReload)
    }

    /// The first of `work` and the budget timer to finish; the timer winning cancels the fetch and gives `fallback`.
    private func raced<T: Sendable>(
        until deadline: ContinuousClock.Instant, fallback: T?, _ work: @escaping @Sendable () async -> T?
    ) async -> T? {
        let value: T?? = await withTaskGroup(of: T??.self) { group in
            group.addTask { .some(await work()) }
            group.addTask {
                try? await Task.sleep(until: deadline)
                return .none
            }
            let first = await group.next() ?? .none
            group.cancelAll()
            return first
        }
        guard let value else {
            await cancelFetch()
            return fallback
        }
        return value ?? fallback
    }

    private func noPlace(_ now: Date) -> (entries: [AuroraEntry], nextReload: Date) {
        ([AuroraEntry(date: now, state: .noPlace, placeName: "")], now.addingTimeInterval(Self.noPlaceDelay))
    }
}
