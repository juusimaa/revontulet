import AuroraCore
import WidgetKit

/// The five designed widget states (data-model.md, WidgetState). The views switch on it.
enum WidgetState: Hashable, Sendable {
    /// A result for the place that is not older than 30 min.
    case current(WidgetSnapshot)
    /// The last result, older than 30 min (also offline with cache): dimmed, "Old data", age.
    case stale(WidgetSnapshot)
    /// No place chosen and nothing cached: "Open Revontulet to choose a place".
    case noPlace
    /// The place is known but there is no valid R value for it: the app's no-data wording.
    case noData
    /// The widget gallery and the redacted placeholder: a plausible sample, marked as one.
    case sample
}

/// What one widget draws at one moment.
struct AuroraEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
    /// The place name in the system language, already resolved by the provider ("" for `noPlace`).
    let placeName: String

    /// The level to draw: the result's in `current` and `stale`, a fixed sample in `sample`, nil otherwise.
    var snapshot: WidgetSnapshot? {
        switch state {
        case .current(let snapshot), .stale(let snapshot): snapshot
        case .sample: Self.sampleSnapshot(at: date)
        case .noPlace, .noData: nil
        }
    }

    var isSample: Bool { state == .sample }

    /// The gallery and placeholder entry. The place is a real town so the layout looks plausible; the
    /// views add the "Sample" marker.
    static func sample(at date: Date) -> AuroraEntry {
        AuroraEntry(date: date, state: .sample, placeName: "Rovaniemi")
    }

    private static func sampleSnapshot(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            level: .moderate, reason: .goodConditions, cloudsIncluded: true, municipalityCode: "698",
            stationName: "Sodankylä", rValue: 118, measuredAt: date.addingTimeInterval(-4 * 60),
            activity: nil, isStale: false)
    }
}
