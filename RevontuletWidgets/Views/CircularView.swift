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
                    if let snapshot = entry.snapshot {
                        RingArc(sweep: Double(snapshot.level.rawValue + 1) / 4 * 0.75, line: line).widgetAccentable()
                    }
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

    /// Old data and nothing-to-show dim only the glyph; the ring stays readable (or empty, which is
    /// not level None: None fills 1 of 4 steps).
    private var opacity: Double { entry.snapshot == nil || entry.snapshot?.isStale == true ? 0.4 : 1 }
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
private let previewNow = Date(timeIntervalSince1970: 1_800_000_000)

private func circularPreview(_ state: WidgetState) -> some View {
    CircularView(entry: AuroraEntry(date: previewNow, state: state, placeName: "Sampletown"))
        .frame(width: 72, height: 72)
        .padding()
        .background(.black)
}

private func previewSnapshot(_ level: ChanceLevel, stale: Bool = false) -> WidgetSnapshot {
    WidgetSnapshot(
        level: level, reason: .goodConditions, cloudsIncluded: true, municipalityCode: "000",
        stationName: "Sample station", rValue: 100, measuredAt: previewNow.addingTimeInterval(-600), isStale: stale)
}

#Preview("None") { circularPreview(.current(previewSnapshot(.none))) }
#Preview("Low") { circularPreview(.current(previewSnapshot(.low))) }
#Preview("Moderate") { circularPreview(.current(previewSnapshot(.moderate))) }
#Preview("High") { circularPreview(.current(previewSnapshot(.high))) }
#Preview("Stale") { circularPreview(.stale(previewSnapshot(.moderate, stale: true))) }
#Preview("No place") { circularPreview(.noPlace) }
#Preview("No data") { circularPreview(.noData) }
#Preview("Sample") { circularPreview(.sample) }
#endif
