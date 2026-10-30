import Foundation

/// Tonight and tomorrow night at a place (specs/003-aurora-outlook/contracts/outlook-rules.md §1).
///
/// A night is a dark period: the time the sun is at or below −6° ("not too light"), sampled every
/// 5 minutes like `SolarPosition.nextDarkness`. Times are sample times; `end` is the first sample
/// that is too light again.
enum Nights {
    static let step: TimeInterval = 5 * 60
    static let maximumLength: TimeInterval = 24 * 3_600
    /// How far ahead a night may start: within 24 hours.
    static let lookahead: TimeInterval = 24 * 3_600

    static func nights(at place: Coordinate, now: Date) -> (tonight: Night, tomorrow: Night) {
        let sky = Sky(place: place)
        let tonightStart: Date?
        if sky.darkness(now) != .tooLight {
            // The period under way: back to its start, at most 24 hours.
            var start = now
            while now.timeIntervalSince(start) < maximumLength, sky.darkness(start - step) != .tooLight {
                start -= step
            }
            tonightStart = start
        } else {
            tonightStart = sky.nextNotTooLight(after: now, within: lookahead)
        }
        guard let tonightStart else { return (.tooLight, .tooLight) }
        let tonight = sky.night(from: tonightStart, relevantFrom: max(now, tonightStart))
        guard let tonightEnd = tonight.end,
              let tomorrowStart = sky.nextNotTooLight(after: tonightEnd - step, within: lookahead)
        else { return (tonight, .tooLight) }
        return (tonight, sky.night(from: tomorrowStart, relevantFrom: tomorrowStart))
    }

    /// `yyyy-MM-dd` in Finnish time (Europe/Helsinki), which decides the storm-watch day of a night.
    static func localDate(_ date: Date) -> String {
        let components = finnishCalendar.dateComponents([.year, .month, .day], from: date)
        func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return "\(components.year!)-\(pad(components.month!))-\(pad(components.day!))"
    }

    private static let finnishCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }()

    private struct Sky {
        let place: Coordinate

        func darkness(_ date: Date) -> Darkness {
            SolarPosition.darkness(latitude: place.latitude, longitude: place.longitude, at: date)
        }

        /// The first sample after `date`, within `limit`, that is not too light.
        func nextNotTooLight(after date: Date, within limit: TimeInterval) -> Date? {
            var candidate = date + step
            while candidate.timeIntervalSince(date) <= limit {
                if darkness(candidate) != .tooLight { return candidate }
                candidate += step
            }
            return nil
        }

        /// The dark period starting at `start`, capped at 24 hours; relevant hours from `relevantFrom`.
        func night(from start: Date, relevantFrom: Date) -> Night {
            var samples: [(time: Date, darkness: Darkness)] = []
            var time = start
            while time.timeIntervalSince(start) < maximumLength {
                let value = darkness(time)
                if value == .tooLight { break }
                samples.append((time, value))
                time += step
            }
            let end = time
            let remaining = samples.filter { $0.time + step > relevantFrom }
            let dark = remaining.filter { $0.darkness == .dark }
            let relevant = dark.isEmpty ? remaining : dark
            return Night(
                start: start, end: end,
                relevantStart: relevant.first.map { max($0.time, relevantFrom) },
                relevantEnd: relevant.last.map { $0.time + step },
                reachesDark: samples.contains { $0.darkness == .dark })
        }
    }
}
