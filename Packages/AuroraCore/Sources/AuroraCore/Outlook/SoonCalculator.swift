import Foundation

/// The "soon" state from real-time solar wind (specs/003-aurora-outlook/contracts/soon-rules.md).
/// Pure: no clock, no network. It never changes the headline (FR-009).
public enum SoonCalculator {
    /// Median Ey (mV/m) from which a band is Possible or Likely.
    public struct Thresholds: Sendable, Hashable {
        public var possible: Double
        public var likely: Double
    }

    /// contracts/soon-rules.md, Thresholds, calibrated in research R6.
    public static func thresholds(for band: Band) -> Thresholds {
        switch band {
        case .north: Thresholds(possible: 1.25, likely: 2.5)
        case .central: Thresholds(possible: 2.5, likely: 5.0)
        case .south: Thresholds(possible: 2.75, likely: 5.5)
        }
    }

    static let windowMinutes = 20
    static let minimumValidMinutes = 15
    static let maximumAge: TimeInterval = 20 * 60
    /// A higher previous state is kept while the driver is at least this share of its threshold.
    static let hysteresis = 0.75

    public static func signal(samples: [SolarWindSample], band: Band, now: Date, previous: SoonState?) -> SoonSignal {
        // 1. The window: 20 minutes of L1 time ending at the newest sample with Bz and speed.
        let complete = samples.filter { $0.bz != nil && $0.speed != nil && $0.time <= now }.sorted { $0.time < $1.time }
        guard let newest = complete.last else { return .unknown }
        let unknown = SoonSignal(state: .unknown, latest: newest, dataTime: newest.time)

        // 2. Unknown when stale or too sparse.
        guard now.timeIntervalSince(newest.time) <= maximumAge else { return unknown }
        let start = newest.time.addingTimeInterval(-Double(windowMinutes - 1) * 60)
        let window = complete.filter { $0.time >= start }
        guard window.count >= minimumValidMinutes else { return unknown }

        // 3–4. The median dawn–dusk electric field.
        let ey = window.map(electricField)
        let driver = median(ey)

        // 5–6. State from the band's thresholds, with hysteresis.
        let thresholds = thresholds(for: band)
        var state: SoonState = driver >= thresholds.likely ? .likely : driver >= thresholds.possible ? .possible : .quiet
        if let previous, let threshold = thresholds.value(for: previous), previous > state,
           driver >= hysteresis * threshold {
            state = previous
        }

        // 7. When the first strong minute of the window reaches Earth.
        var arrivalMinutes: Int?
        if let threshold = thresholds.value(for: state) {
            // A state kept by hysteresis has a driver below its threshold; the median minute counts.
            let strong = min(threshold, driver)
            if let first = zip(window, ey).first(where: { $0.1 >= strong && $0.0.arrival != nil })?.0.arrival {
                arrivalMinutes = rounded(minutes: first.timeIntervalSince(now) / 60)
            }
        }
        return SoonSignal(state: state, driver: driver, arrivalMinutes: arrivalMinutes, latest: newest, dataTime: newest.time)
    }

    /// FR-010: the line is hidden when it is too light at the place now and at the arrival time.
    /// Only `OutlookService` calls this, off the main actor.
    public static func showsOnMainScreen(_ signal: SoonSignal, at place: Coordinate, now: Date) -> Bool {
        guard signal.state == .possible || signal.state == .likely else { return false }
        func tooLight(_ date: Date) -> Bool {
            SolarPosition.darkness(latitude: place.latitude, longitude: place.longitude, at: date) == .tooLight
        }
        let arrival = now.addingTimeInterval(Double(signal.arrivalMinutes ?? 0) * 60)
        return !(tooLight(now) && tooLight(arrival))
    }

    /// Ey = speed × southward Bz / 1000, in mV/m; northward Bz gives 0.
    static func electricField(_ sample: SolarWindSample) -> Double {
        (sample.speed ?? 0) * max(0, -(sample.bz ?? 0)) / 1000
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Rounded to the nearest 15 minutes, at least 15; 60 stands for "about an hour" or more.
    static func rounded(minutes: Double) -> Int {
        min(60, max(15, Int((minutes / 15).rounded()) * 15))
    }
}

extension SoonCalculator.Thresholds {
    func value(for state: SoonState) -> Double? {
        switch state {
        case .possible: possible
        case .likely: likely
        case .quiet, .unknown: nil
        }
    }
}
