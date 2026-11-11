import AuroraCore
import SwiftUI
import WidgetKit

/// The inline Lock Screen widget: one line above the clock. It shows no age, so old data says so
/// in the wording itself (FR-007).
struct InlineView: View {
    let entry: AuroraEntry

    var body: some View {
        ViewThatFits {
            Label { Text(full) } icon: { Image(systemName: "sparkles") }
            Label { Text(short) } icon: { Image(systemName: "sparkles") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetFormat.accessibilityLabel(for: entry))
    }

    private var level: String? { entry.snapshot.map { String(localized: $0.level.title) } }

    /// "Aurora: Moderate · Oulu", or "Old data · Moderate" when stale.
    private var full: String {
        guard let snapshot = entry.snapshot, let level else { return entry.placeName }
        if snapshot.isStale { return String(localized: "Old data · \(level)") }
        return String(localized: "Aurora: \(level) · \(entry.placeName)")
    }

    /// Without the place: "Aurora: Moderate", or "Old data · Moderate".
    private var short: String {
        guard let snapshot = entry.snapshot, let level else { return String(localized: "Aurora") }
        if snapshot.isStale { return full }
        return String(localized: "Aurora: \(level)")
    }
}
