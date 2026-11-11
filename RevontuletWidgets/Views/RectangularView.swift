import AuroraCore
import SwiftUI
import WidgetKit

/// The rectangular Lock Screen widget: place, level word, a four-step gauge and reason · age. No
/// custom colours or background; the system tints it (vibrant or accented).
struct RectangularView: View {
    let entry: AuroraEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if entry.state == .noPlace {
                HStack(alignment: .top, spacing: 4) {
                    AuroraGlyph().frame(width: 12, height: 12).padding(.top, 2)
                    Text("Open Revontulet to choose a place")
                        .font(.caption.weight(.semibold))
                        .lineLimit(3)
                }
            } else {
                header
                if let snapshot = entry.snapshot {
                    Text(snapshot.level.title)
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .widgetAccentable()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 2) {
                        ForEach(1...4, id: \.self) { step in
                            if step <= snapshot.level.rawValue + 1 {
                                Capsule().widgetAccentable()
                            } else {
                                Capsule().opacity(0.28)
                            }
                        }
                    }
                    .frame(height: 4)
                    bottomLine(snapshot)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text("No aurora data right now")
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetFormat.accessibilityLabel(for: entry))
    }

    private var header: some View {
        HStack(spacing: 4) {
            AuroraGlyph()
                .frame(width: 12, height: 12)
            Text(verbatim: entry.isSample ? "\(entry.placeName) · \(String(localized: "Sample"))" : entry.placeName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .opacity(0.75)
    }

    private func bottomLine(_ snapshot: WidgetSnapshot) -> some View {
        WidgetFormat.LeadAndAge(
            lead: snapshot.isStale ? String(localized: "Old data") : String(localized: snapshot.reason.title),
            age: WidgetFormat.ageText(of: snapshot.measuredAt, at: entry.date))
    }
}

#if DEBUG
private func rectanglePreview(_ state: WidgetState, place: String = "Sampletown") -> some View {
    RectangularView(entry: AuroraEntry(date: previewNow, state: state, placeName: place))
        .frame(width: 160, height: 72)
        .background(.black)
        .foregroundStyle(.white)
}

private let previewNow = Date(timeIntervalSince1970: 1_800_000_000)

private func previewSnapshot(stale: Bool) -> WidgetSnapshot {
    WidgetSnapshot(
        level: .moderate, reason: .goodConditions, cloudsIncluded: true, municipalityCode: "000",
        stationName: "Sample station", rValue: 100, measuredAt: previewNow.addingTimeInterval(stale ? -7200 : -720),
        isStale: stale)
}

#Preview("Current") { rectanglePreview(.current(previewSnapshot(stale: false))) }
#Preview("Stale") { rectanglePreview(.stale(previewSnapshot(stale: true))) }
#Preview("No place") { rectanglePreview(.noPlace, place: "") }
#Preview("No data") { rectanglePreview(.noData) }
#Preview("Sample") { rectanglePreview(.sample, place: "Rovaniemi") }
#endif
