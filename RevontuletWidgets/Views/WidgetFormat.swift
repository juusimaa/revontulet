import AuroraCore
import SwiftUI

/// Text shared by the widget layouts: the data age and the one-sentence VoiceOver label.
enum WidgetFormat {
    /// "Just now", "12 min ago", "3 h ago", "2 d ago", relative to the entry's own date.
    static func age(of measuredAt: Date, at now: Date) -> LocalizedStringResource {
        let minutes = max(0, Int(now.timeIntervalSince(measuredAt) / 60))
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        if minutes < 60 * 24 { return "\(minutes / 60) h ago" }
        return "\(minutes / (60 * 24)) d ago"
    }

    /// "<Level>, <reason>, <place>, <age>" (contracts/widget-refresh.md, Accessibility).
    static func accessibilityLabel(for entry: AuroraEntry) -> String {
        guard let snapshot = entry.snapshot else { return entry.placeName }
        let level = String(localized: snapshot.level.title)
        let reason = String(localized: snapshot.reason.title)
        let age = String(localized: age(of: snapshot.measuredAt, at: entry.date))
        return String(localized: "\(level), \(reason), \(entry.placeName), \(age)")
    }
}
