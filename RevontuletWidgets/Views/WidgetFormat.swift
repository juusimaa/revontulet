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

    /// The age for display: spaces made non-breaking so "10 t sitten" never splits across lines.
    static func ageText(of measuredAt: Date, at now: Date) -> String {
        String(localized: age(of: measuredAt, at: now)).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// One VoiceOver sentence per state (contracts/widget-refresh.md, Accessibility):
    /// "<Level>, <reason>, <place>, <age>", or when stale "Old data, <age>, last level <Level>, <reason>, <place>".
    static func accessibilityLabel(for entry: AuroraEntry) -> String {
        switch entry.state {
        case .noPlace:
            return String(localized: "Open Revontulet to choose a place")
        case .noData:
            return [entry.placeName, String(localized: "No aurora data right now")]
                .filter { !$0.isEmpty }.joined(separator: ", ")
        case .current, .stale, .sample:
            guard let snapshot = entry.snapshot else { return entry.placeName }
            let level = String(localized: snapshot.level.title)
            let reason = String(localized: snapshot.reason.title)
            let age = String(localized: age(of: snapshot.measuredAt, at: entry.date))
            let sentence = snapshot.isStale
                ? String(localized: "Old data, \(age), last level \(level), \(reason), \(entry.placeName)")
                : String(localized: "\(level), \(reason), \(entry.placeName), \(age)")
            return entry.isSample ? "\(String(localized: "Sample")), \(sentence)" : sentence
        }
    }
}
