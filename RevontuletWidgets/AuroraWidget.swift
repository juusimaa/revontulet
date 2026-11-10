import SwiftUI
import WidgetKit

// Placeholder that proves the extension builds and embeds (T006). US1 replaces the provider,
// the entry and the views (contracts/widget-refresh.md).

struct AuroraWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AuroraWidget", provider: PlaceholderProvider()) { _ in
            Text(verbatim: "Revontulet")
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName(Text(verbatim: "Revontulet"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}

private struct PlaceholderEntry: TimelineEntry {
    let date: Date
}
