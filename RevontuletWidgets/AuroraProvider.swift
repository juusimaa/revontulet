import AuroraCore
import Foundation
import WidgetKit

/// Builds the widget entries from what the app cached in the App Group. Cache only for now: it never
/// fetches (contracts/widget-refresh.md, steps 1-2 and 5-7).
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

    func placeholder(in context: Context) -> AuroraEntry {
        AuroraEntry(date: now(), snapshot: nil, placeName: "")
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (AuroraEntry) -> Void) {
        Task { completion(await build().entry) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AuroraEntry>) -> Void) {
        Task {
            let built = await build()
            completion(Timeline(entries: [built.entry], policy: .after(built.nextReload)))
        }
    }

    /// The entry for the current moment and when to reload next.
    func build() async -> (entry: AuroraEntry, nextReload: Date) {
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
            guard let cached else { return noPlace(now) }
            code = cached.place.municipalityCode
            coordinate = cached.place.coordinate
        }

        let placeName = (try? MunicipalityNames.lookup(code: code))?
            .displayName(preferSwedish: prefersSwedish) ?? ""
        let nextReload = WidgetRefreshPolicy.nextReload(after: now, at: coordinate)

        // The widget never shows another place's result.
        guard let cached, cached.place.municipalityCode == code else {
            return (AuroraEntry(date: now, snapshot: nil, placeName: placeName), nextReload)
        }
        let outlook = await loadOutlook()
        let snapshot = WidgetSnapshot.make(result: cached, outlook: outlook, now: now)
        return (AuroraEntry(date: now, snapshot: snapshot, placeName: placeName), nextReload)
    }

    private func noPlace(_ now: Date) -> (entry: AuroraEntry, nextReload: Date) {
        (AuroraEntry(date: now, snapshot: nil, placeName: ""), now.addingTimeInterval(Self.noPlaceDelay))
    }
}
