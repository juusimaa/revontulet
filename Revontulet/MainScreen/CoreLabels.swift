import AuroraCore
import Foundation

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

enum Formatting {
    static func distance(_ km: Double) -> String {
        Measurement(value: km.rounded(), unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// "8 min ago", localised; never in the future.
    static func age(of date: Date, now: Date) -> String {
        min(date, now).formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
