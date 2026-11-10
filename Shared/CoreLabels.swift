import AuroraCore
import Foundation
import SwiftUI

// User-facing text for core values. Keys live in Localizable.xcstrings (en, fi, sv).

extension ChanceLevel {
    var title: LocalizedStringResource {
        switch self {
        case .none: "level.none"
        case .low: "level.low"
        case .moderate: "level.moderate"
        case .high: "level.high"
        }
    }
}

extension ChanceReason {
    var title: LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key))
    }
}

extension ActivityLevel {
    /// FMI's own wording, e.g. "Revontulet mahdollisia".
    var title: LocalizedStringResource {
        switch self {
        case .unlikely: "activity.unlikely"
        case .possible: "activity.possible"
        case .probable: "activity.probable"
        }
    }
}

extension Darkness {
    var title: LocalizedStringResource {
        switch self {
        case .tooLight: "darkness.tooLight"
        case .twilight: "darkness.twilight"
        case .dark: "darkness.dark"
        }
    }
}

extension MoonPhase {
    /// e.g. "waxing gibbous"; used inside a sentence.
    var title: LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key))
    }
}

extension MoonState {
    /// Illuminated part in whole percent.
    var percentLit: Int { Int((illuminatedFraction * 100).rounded()) }
}

extension CloudCondition {
    var title: LocalizedStringResource {
        switch self {
        case .clear: "clouds.clear"
        case .partly: "clouds.partly"
        case .overcast: "clouds.overcast"
        case .unknown: "clouds.unknown"
        }
    }
}

// MARK: Soon (specs/003-aurora-outlook/contracts/soon-rules.md, Display)

extension SoonSignal {
    /// The main-screen line, or nil for Quiet and Unknown. With Probable activity already
    /// measured, the line talks about it continuing instead of rising.
    func line(headlineActivity: ActivityLevel?) -> Text? {
        let continuing = headlineActivity == .probable
        switch state {
        case .likely where continuing: return Text("Activity likely to continue")
        case .possible where continuing: return Text("Activity may stay high")
        case .likely: return window.map { Text("Activity likely to rise \($0)") } ?? Text("Activity likely to rise")
        case .possible: return window.map { Text("Activity may rise \($0)") } ?? Text("Activity may rise")
        case .quiet, .unknown: return nil
        }
    }

    /// "within about 30 minutes" or "within about an hour".
    var window: Text? {
        guard let arrivalMinutes else { return nil }
        return arrivalMinutes >= 60 ? Text("within about an hour") : Text("within about \(arrivalMinutes) minutes")
    }

    /// The state in the details, always shown (FR-010).
    func detail(headlineActivity: ActivityLevel?) -> Text {
        switch state {
        case .quiet: headlineActivity == .probable ? Text("No sign of further rise") : Text("No sign of rising activity")
        case .unknown: Text("Solar wind data unavailable")
        case .possible, .likely: line(headlineActivity: headlineActivity) ?? Text("Solar wind data unavailable")
        }
    }
}

// MARK: Outlook (specs/003-aurora-outlook/contracts/outlook-rules.md, Display)

extension NightKind {
    var title: LocalizedStringResource {
        switch self {
        case .tonight: "Tonight"
        case .tomorrow: "Tomorrow night"
        }
    }
}

extension NightOutlook {
    /// Tonight's dark period has started: the outlook covers only the rest of it.
    func isUnderway(at now: Date) -> Bool {
        guard which == .tonight, let start = night.start else { return false }
        return start <= now
    }

    /// "Tonight", or "Rest of tonight" once the night is under way.
    func title(at now: Date) -> LocalizedStringResource {
        isUnderway(at: now) ? "Rest of tonight" : which.title
    }

    /// The measurement is above this night's expected activity while the night is under way.
    /// Only that way round: a forecast above the measurement may still come true later.
    func isExceeded(by measured: ActivityLevel?, at now: Date) -> Bool {
        guard isUnderway(at: now), availability == .available, let measured, let activity,
              let measuredRank = ActivityLevel.allCases.firstIndex(of: measured),
              let expectedRank = ActivityLevel.allCases.firstIndex(of: activity) else { return false }
        return measuredRank > expectedRank
    }
}

extension OutlookReason {
    var title: LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key))
    }
}

extension OutlookAvailability {
    var title: LocalizedStringResource {
        switch self {
        case .available: "Forecast available"
        case .tooLight: "reason.tooLight"
        case .unavailable: "Outlook unavailable"
        }
    }
}

/// NOAA's geomagnetic storm scale in plain language.
enum StormLevel {
    static func title(_ level: Int) -> LocalizedStringResource {
        switch level {
        case 1: "storm.g1"
        case 2: "storm.g2"
        case 3: "storm.g3"
        case 4: "storm.g4"
        default: "storm.g5"
        }
    }
}

enum Formatting {
    static func distance(_ km: Double) -> String {
        Measurement(value: km.rounded(), unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// Kp in the forecast's thirds, e.g. 4.67 → "4.7".
    static func kp(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// "8 min ago", localised; never in the future.
    static func age(of date: Date, now: Date) -> String {
        Date.AnchoredRelativeFormatStyle(anchor: min(date, now), presentation: .named, unitsStyle: .abbreviated)
            .format(now)
    }
}
