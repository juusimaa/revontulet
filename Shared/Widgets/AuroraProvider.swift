import AuroraCore
import Foundation
import WidgetKit

/// Builds the widget entries from what the app cached in the App Group. Cache only for now: it never
/// fetches. Lives in `Shared/` so the app's unit tests can reach it.
struct AuroraProvider: TimelineProvider {
    typealias Entry = AuroraEntry

    /// How long to wait before asking again when there is no place to show (FR-021).
    static let noPlaceDelay: TimeInterval = 60 * 60

    let loadResult: @Sendable () async -> AuroraResult?
    let loadOutlook: @Sendable () async -> OutlookSnapshot?
    let readSelection: @Sendable () -> PlaceSelection
    let now: @Sendable () -> Date
    let prefersSwedish: Bool

    init(
        loadResult: @escaping @Sendable () async -> AuroraResult? = { await FileResultCache().load() },
        loadOutlook: @escaping @Sendable () async -> OutlookSnapshot? = { await FileOutlookCache().load() },
        readSelection: @escaping @Sendable () -> PlaceSelection = { PlaceSelectionStore().selection },
        now: @escaping @Sendable () -> Date = { Date() },
        prefersSwedish: Bool = Bundle.main.preferredLocalizations.first == "sv"
    ) {
        self.loadResult = loadResult
        self.loadOutlook = loadOutlook
        self.readSelection = readSelection
        self.now = now
        self.prefersSwedish = prefersSwedish
    }

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
        Task { completion(await build().entries[0]) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AuroraEntry>) -> Void) {
        Task {
            let built = await build()
            completion(Timeline(entries: built.entries, policy: .after(built.nextReload)))
        }
    }

    /// The entries from now on (the current one, then the moment it turns stale if that is still ahead)
    /// and when to reload next (contracts/widget-refresh.md, steps 1-2 and 5-7).
    func build() async -> (entries: [AuroraEntry], nextReload: Date) {
        let now = now()
        let selection = readSelection()
        let cached = await loadResult()

        let code: String
        let coordinate: Coordinate
        switch selection {
        case .municipality(let selectedCode):
            guard let name = try? MunicipalityNames.lookup(code: selectedCode) else {
                return noPlace(now)
            }
            code = name.code
            coordinate = name.representativePoint
        case .currentLocation:
            // Outside coverage the app never stores a result, so this is also the out-of-coverage case.
            guard let cached else { return noPlace(now) }
            code = cached.place.municipalityCode
            coordinate = cached.place.coordinate
        }

        let placeName = (try? MunicipalityNames.lookup(code: code))?
            .displayName(preferSwedish: prefersSwedish) ?? ""
        let nextReload = WidgetRefreshPolicy.nextReload(after: now, at: coordinate)

        // The widget never shows another place's result, nor a level without a valid R value.
        guard let cached, cached.place.municipalityCode == code, cached.reading.r != nil else {
            return ([AuroraEntry(date: now, state: .noData, placeName: placeName)], nextReload)
        }
        let outlook = await loadOutlook()
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

    private func noPlace(_ now: Date) -> (entries: [AuroraEntry], nextReload: Date) {
        ([AuroraEntry(date: now, state: .noPlace, placeName: "")], now.addingTimeInterval(Self.noPlaceDelay))
    }
}
