import AuroraCore
import SwiftUI
import WidgetKit

/// The rectangular Lock Screen widget: place, level word, a four-step gauge and reason · age. No
/// custom colours or background; the system tints it (vibrant or accented).
struct RectangularView: View {
    let entry: AuroraEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                AuroraGlyph(level: entry.snapshot?.level)
                    .frame(width: 12, height: 12)
                Text(entry.placeName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .opacity(0.75)
            if let snapshot = entry.snapshot {
                let dim = snapshot.isStale ? 0.55 : 1.0
                Text(snapshot.level.title)
                    .font(.headline.weight(.heavy))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(dim)
                HStack(spacing: 2) {
                    ForEach(1...4, id: \.self) { step in
                        if step <= snapshot.level.rawValue + 1 {
                            Capsule().widgetAccentable().opacity(dim)
                        } else {
                            Capsule().opacity(0.28)
                        }
                    }
                }
                .frame(height: 4)
                bottomLine(snapshot)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetFormat.accessibilityLabel(for: entry))
    }

    private func bottomLine(_ snapshot: WidgetSnapshot) -> Text {
        let age = String(localized: WidgetFormat.age(of: snapshot.measuredAt, at: entry.date))
        if snapshot.isStale { return Text("Old data · \(age)") }
        return Text(verbatim: "\(String(localized: snapshot.reason.title)) · \(age)")
    }
}

#if DEBUG
private func rectanglePreview(stale: Bool) -> some View {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = WidgetSnapshot(
        level: .moderate, reason: .goodConditions, cloudsIncluded: true, municipalityCode: "000",
        stationName: "Sample station", rValue: 100, measuredAt: now.addingTimeInterval(stale ? -7200 : -720),
        isStale: stale)
    return RectangularView(entry: AuroraEntry(date: now, snapshot: snapshot, placeName: "Sampletown"))
        .frame(width: 160, height: 72)
        .background(.black)
        .foregroundStyle(.white)
}

#Preview("Moderate") { rectanglePreview(stale: false) }
#Preview("Moderate stale") { rectanglePreview(stale: true) }
#endif
