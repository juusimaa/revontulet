import Foundation

/// When the widgets fetch fresh data and when they ask the system for the next timeline reload.
public enum WidgetRefreshPolicy {
    /// The shortest input interval: the magnetometers publish every 5 minutes.
    static let magnetometerInterval: TimeInterval = 5 * 60
    static let step: TimeInterval = 15 * 60
    static let maxReloadDelay: TimeInterval = 3 * 3600

    /// true when a fetch is needed: no cached result, another municipality, a future computedAt
    /// (clock moved), or the result is at least as old as the magnetometer interval (5 min;
    /// 4:59 is fresh, 5:00 is due).
    public static func resultNeedsFetch(cached: AuroraResult?, place: Place, now: Date) -> Bool {
        guard let cached, cached.place.municipalityCode == place.municipalityCode else { return true }
        return isDue(computedAt: cached.computedAt, now: now)
    }

    /// Same rule for the outlook snapshot (medium widget only).
    public static func outlookNeedsFetch(cached: OutlookSnapshot?, place: Place, now: Date) -> Bool {
        guard let cached, cached.place.municipalityCode == place.municipalityCode else { return true }
        return isDue(computedAt: cached.computedAt, now: now)
    }

    /// The reload date to suggest to the system: `now + 15 min` while it is not too light at
    /// `coordinate`; otherwise 15 min before the next time it is not too light (15-minute steps
    /// over 24 hours), within `now + 15 min ... now + 3 h`.
    public static func nextReload(after now: Date, at coordinate: Coordinate) -> Date {
        let earliest = now.addingTimeInterval(step)
        let latest = now.addingTimeInterval(maxReloadDelay)
        func tooLight(at date: Date) -> Bool {
            SolarPosition.darkness(latitude: coordinate.latitude, longitude: coordinate.longitude, at: date) == .tooLight
        }
        if !tooLight(at: now) { return earliest }
        let steps = Int(86_400 / step)
        guard let index = (1...steps).first(where: { !tooLight(at: now.addingTimeInterval(Double($0) * step)) }) else {
            return latest
        }
        let target = now.addingTimeInterval(Double(index) * step - step)
        return min(max(target, earliest), latest)
    }

    /// The moment a result measured at `measuredAt` turns stale.
    public static func staleMoment(measuredAt: Date) -> Date {
        measuredAt.addingTimeInterval(AuroraResult.outdatedAfter)
    }

    private static func isDue(computedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(computedAt)
        return age < 0 || age >= magnetometerInterval
    }
}
