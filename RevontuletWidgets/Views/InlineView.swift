import AuroraCore
import SwiftUI
import WidgetKit

/// The inline Lock Screen widget: one line above the clock, with the aurora glyph as a custom symbol
/// (inline widgets draw only text and symbols). It shows no age, so old data says so
/// in the wording itself (FR-007).
struct InlineView: View {
    let entry: AuroraEntry

    var body: some View {
        ViewThatFits {
            Label { Text(full) } icon: { Image("aurora") }
            Label { Text(short) } icon: { Image("aurora") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetFormat.accessibilityLabel(for: entry))
    }

    /// "Aurora: Moderate · Oulu", "Old data · Moderate" when stale, or the no-place / no-data wording.
    private var full: String {
        switch entry.state {
        case .noPlace: String(localized: "Open Revontulet to choose a place")
        case .noData: String(localized: "Aurora: \(String(localized: "No data"))")
        case .stale: String(localized: "Old data · \(level)")
        case .current, .sample: String(localized: "Aurora: \(level) · \(entry.placeName)")
        }
    }

    /// Without the place: "Aurora: Moderate", "Old data · Moderate", or just "Aurora" with no place.
    private var short: String {
        switch entry.state {
        case .noPlace: String(localized: "Aurora")
        case .current, .sample: String(localized: "Aurora: \(level)")
        case .stale, .noData: full
        }
    }

    private var level: String { entry.snapshot.map { String(localized: $0.level.title) } ?? "" }
}

#if DEBUG
private func inlinePreview(_ state: WidgetState, place: String = "Sampletown") -> some View {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    return InlineView(entry: AuroraEntry(date: now, state: state, placeName: place)).background(.black)
}

private let previewSnapshot = WidgetSnapshot(
    level: .moderate, reason: .goodConditions, cloudsIncluded: true, municipalityCode: "000",
    stationName: "Sample station", rValue: 100, measuredAt: Date(timeIntervalSince1970: 1_800_000_000 - 600), isStale: false)

#Preview("Current") { inlinePreview(.current(previewSnapshot)) }
#Preview("Stale") { inlinePreview(.stale(previewSnapshot)) }
#Preview("No place") { inlinePreview(.noPlace, place: "") }
#Preview("No data") { inlinePreview(.noData) }
#Preview("Sample") { inlinePreview(.sample, place: "Rovaniemi") }
#endif
