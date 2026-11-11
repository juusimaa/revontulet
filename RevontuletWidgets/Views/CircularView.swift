import AuroraCore
import SwiftUI
import WidgetKit

/// The circular Lock Screen widget: a gauge ring (270° arc, gap at the bottom) filled by level, with
/// the aurora glyph in the middle. No words (FR-005); the level is the fill amount (FR-006).
struct CircularView: View {
    let entry: AuroraEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let line = side * 5 / 72
                ZStack {
                    RingArc(sweep: 0.75, line: line).opacity(0.3)
                    RingArc(sweep: fill * 0.75, line: line).widgetAccentable().opacity(opacity)
                    AuroraGlyph()
                        .frame(width: side * 0.4, height: side * 0.4)
                        .widgetAccentable()
                        .opacity(opacity)
                }
                .padding(line / 2)
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetFormat.accessibilityLabel(for: entry))
    }

    /// Share of the sweep that is filled: step / 4, where step = level + 1 (Moderate fills 3 of 4).
    private var fill: Double {
        guard let snapshot = entry.snapshot else { return 0 }
        return Double(snapshot.level.rawValue + 1) / 4
    }

    private var opacity: Double { entry.snapshot?.isStale == true ? 0.5 : 1 }
}

/// An arc starting at 135° (bottom left) sweeping clockwise by `sweep` of a full circle.
private struct RingArc: View {
    let sweep: Double
    let line: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0, to: sweep)
            .stroke(style: StrokeStyle(lineWidth: line, lineCap: .round))
            .rotationEffect(.degrees(135))
    }
}

#if DEBUG
private struct CircularPreviewFrame: View {
    let level: ChanceLevel?
    var stale = false

    var body: some View {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = level.map {
            WidgetSnapshot(
                level: $0, reason: .goodConditions, cloudsIncluded: true, municipalityCode: "000",
                stationName: "Sample station", rValue: 100, measuredAt: now.addingTimeInterval(-600), isStale: stale)
        }
        CircularView(entry: AuroraEntry(date: now, snapshot: snapshot, placeName: "Sampletown"))
            .frame(width: 72, height: 72)
            .padding()
            .background(.black)
    }
}

#Preview("None") { CircularPreviewFrame(level: ChanceLevel.none) }
#Preview("Low") { CircularPreviewFrame(level: .low) }
#Preview("Moderate") { CircularPreviewFrame(level: .moderate) }
#Preview("High") { CircularPreviewFrame(level: .high) }
#Preview("Stale") { CircularPreviewFrame(level: .moderate, stale: true) }
#Preview("No data") { CircularPreviewFrame(level: nil) }
#endif
