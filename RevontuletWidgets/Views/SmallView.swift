import AuroraCore
import SwiftUI

/// The level colours of the widget draft (L-high / L-mod / L-low / L-none). The app has no shared
/// level tint (its main screen draws the level in white over the sky), so they live here; the
/// medium and Lock Screen layouts can reuse them.
extension ChanceLevel {
    var widgetTint: Color {
        switch self {
        case .high: Color(red: 1.0, green: 0.435, blue: 0.847)      // #ff6fd8, magenta only for High
        case .moderate: Color(red: 0.365, green: 1.0, blue: 0.69)   // #5dffb0
        case .low: Color(red: 1.0, green: 0.827, blue: 0.42)        // #ffd36b
        case .none: Color(red: 0.725, green: 0.776, blue: 0.8)      // #b9c6cc
        }
    }
}

/// The small Home Screen widget: the level word first and largest, the reason under it, then place
/// and data age. The caller supplies the background: `containerBackground(for: .widget)` with
/// `SmallView.background(for:)`.
struct SmallView: View {
    let entry: AuroraEntry

    static func background(for entry: AuroraEntry) -> some View {
        WidgetSky(level: entry.snapshot?.level, isStale: entry.snapshot?.isStale ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuroraGlyph(level: entry.snapshot?.level)
                .frame(width: 16, height: 16)
                .foregroundStyle(tint)
            Spacer(minLength: 4)
            if let snapshot = entry.snapshot {
                Text(snapshot.level.title)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(snapshot.reason.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .padding(.top, 2)
                Text("\(entry.placeName) · \(String(localized: WidgetFormat.age(of: snapshot.measuredAt, at: entry.date)))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 6)
            } else if !entry.placeName.isEmpty {
                Text(entry.placeName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetFormat.accessibilityLabel(for: entry))
    }

    private var tint: Color { entry.snapshot?.level.widgetTint ?? ChanceLevel.none.widgetTint }
}

#if DEBUG
private enum SmallPreviewData {
    static func entry(_ level: ChanceLevel, _ reason: ChanceReason, place: String, minutes: Int, stale: Bool = false) -> AuroraEntry {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = WidgetSnapshot(
            level: level, reason: reason, cloudsIncluded: true, municipalityCode: "000", stationName: "Sample station",
            rValue: 100, measuredAt: now.addingTimeInterval(TimeInterval(-minutes * 60)), isStale: stale)
        return AuroraEntry(date: now, snapshot: snapshot, placeName: place)
    }
}

private struct SmallPreviewFrame: View {
    let entry: AuroraEntry
    var body: some View {
        SmallView(entry: entry)
            .padding(16)
            .frame(width: 158, height: 158)
            .background { SmallView.background(for: entry) }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding()
    }
}

#Preview("Moderate") { SmallPreviewFrame(entry: SmallPreviewData.entry(.moderate, .goodConditions, place: "Sampletown", minutes: 12)) }
#Preview("High") { SmallPreviewFrame(entry: SmallPreviewData.entry(.high, .goodConditions, place: "Sampletown", minutes: 3)) }
#Preview("Low") { SmallPreviewFrame(entry: SmallPreviewData.entry(.low, .lowActivity, place: "Sampletown", minutes: 8)) }
#Preview("None") { SmallPreviewFrame(entry: SmallPreviewData.entry(.none, .tooLight, place: "Sampletown", minutes: 5)) }
#Preview("No data") { SmallPreviewFrame(entry: AuroraEntry(date: .now, snapshot: nil, placeName: "Sampletown")) }
#endif
