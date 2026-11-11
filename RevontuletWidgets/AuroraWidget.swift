import SwiftUI
import WidgetKit

/// The Home Screen widget: the aurora chance from the last stored result. No `widgetURL`, so a tap
/// opens the app on its main screen (FR-010).
struct AuroraWidget: Widget {
    static let kind = "AuroraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AuroraProvider()) { entry in
            AuroraWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Aurora"))
        .description(Text("How likely you are to see aurora from your place"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct AuroraWidgetView: View {
    let entry: AuroraEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: MediumView(entry: entry)
            default: SmallView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            WidgetSky(level: entry.snapshot?.level, isStale: entry.snapshot?.isStale ?? false)
        }
    }
}
