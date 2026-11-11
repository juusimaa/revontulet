import AuroraCore
import SwiftUI
import WidgetKit

// TEMP spike (T022): render the sky in a widget background.
struct AuroraWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AuroraWidget", provider: SpikeProvider()) { entry in
            VStack(alignment: .leading) {
                Text(verbatim: "Oulu").font(.caption).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(verbatim: "High").font(.title.bold()).foregroundStyle(.white)
                Text(verbatim: "Go outside now").font(.footnote).foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { WidgetSky(level: .high) }
        }
        .configurationDisplayName(Text(verbatim: "Revontulet"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry { SpikeEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) { completion(SpikeEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [SpikeEntry(date: .now)], policy: .never))
    }
}

private struct SpikeEntry: TimelineEntry { let date: Date }
