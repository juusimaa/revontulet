import SwiftUI
import WidgetKit

/// The Home Screen and Lock Screen widget: the aurora chance from the last stored result. No `widgetURL`, so a tap
/// opens the app on its main screen (FR-010).
struct AuroraWidget: Widget {
    static let kind = "AuroraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AuroraProvider()) { entry in
            AuroraWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Aurora"))
        .description(Text("How likely you are to see aurora from your place"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct AuroraWidgetView: View {
    let entry: AuroraEntry
    @Environment(\.widgetFamily) private var family
    private static let lockScreen: Set<WidgetFamily> = [.accessoryCircular, .accessoryRectangular, .accessoryInline]

    var body: some View {
        Group {
            switch family {
            case .systemMedium: MediumView(entry: entry)
            case .accessoryCircular: CircularView(entry: entry)
            case .accessoryRectangular: RectangularView(entry: entry)
            case .accessoryInline: InlineView(entry: entry)
            default: SmallView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            // Lock Screen families keep the system background and vibrancy (contracts/widget-refresh.md).
            if !Self.lockScreen.contains(family) {
                WidgetSky(level: entry.snapshot?.level, isStale: entry.snapshot?.isStale ?? false)
            }
        }
    }
}
