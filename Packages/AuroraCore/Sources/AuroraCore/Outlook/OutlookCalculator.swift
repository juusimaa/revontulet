import Foundation

/// The outlook for tonight and tomorrow night (specs/003-aurora-outlook/contracts/outlook-rules.md).
/// Pure: the sun and moon are computed for the place inside; the level comes from
/// `ChanceCalculator`, so an outlook and the headline combine the factors the same way.
public enum OutlookCalculator {
    /// Kp from which a band's expected activity is Possible or Probable.
    public struct Thresholds: Sendable, Hashable {
        public var possibleFrom: Double
        public var probableFrom: Double
    }

    /// contracts/outlook-rules.md §2, calibrated in research R7. Kp is given in thirds (2.67 is "3−").
    public static func thresholds(for band: Band) -> Thresholds {
        switch band {
        case .north: Thresholds(possibleFrom: 1, probableFrom: 2.67)
        case .central: Thresholds(possibleFrom: 2.67, probableFrom: 4)
        case .south: Thresholds(possibleFrom: 5, probableFrom: 5.67)
        }
    }

    public static func outlook(
        place: Coordinate, band: Band, now: Date, kp: KpForecast?, watches: [StormWatch], clouds: CloudForecast?
    ) -> Outlook {
        let nights = Nights.nights(at: place, now: now)
        func outlook(_ which: NightKind, _ night: Night) -> NightOutlook {
            nightOutlook(which, night, place: place, band: band, kp: kp, watches: watches, clouds: clouds)
        }
        return Outlook(tonight: outlook(.tonight, nights.tonight), tomorrow: outlook(.tomorrow, nights.tomorrow), computedAt: now)
    }

    /// Kp values are thirds (4.67 for "5−"); compare with a little slack.
    static let epsilon = 0.01
    static let sampleStep: TimeInterval = 5 * 60

    static func activity(kp: Double, band: Band) -> ActivityLevel {
        let thresholds = thresholds(for: band)
        if kp >= thresholds.probableFrom - epsilon { return .probable }
        if kp >= thresholds.possibleFrom - epsilon { return .possible }
        return .unlikely
    }

    private static func nightOutlook(
        _ which: NightKind, _ night: Night, place: Coordinate, band: Band, kp: KpForecast?, watches: [StormWatch],
        clouds: CloudForecast?
    ) -> NightOutlook {
        guard let start = night.start, let from = night.relevantStart, let to = night.relevantEnd else {
            return NightOutlook(
                which: which, night: night, availability: .tooLight, darkness: .tooLight,
                chance: Chance(level: .none, limitingFactor: .light, cloudsIncluded: true), reason: .chance(.tooLight),
                kpFetchedAt: kp?.fetchedAt, cloudsFetchedAt: clouds?.fetchedAt)
        }

        // §2 Expected activity: the forecast over the relevant hours, raised by a watch for the
        // night that starts on the watch's date in Finland.
        let forecastKp = kp?.blocks.filter { $0.start < to && $0.end > from }.map(\.kp).max()
        let localStart = Nights.localDate(start)
        let watchLevel = watches.filter { $0.days.contains(localStart) }.map(\.level).max()
        let watchKp = watchLevel.map { Double(4 + $0) }

        // §3 Sky over the relevant hours.
        let times = stride(from: from.timeIntervalSince1970, to: to.timeIntervalSince1970, by: sampleStep)
            .map(Date.init(timeIntervalSince1970:))
        let darkness: Darkness = times.contains {
            SolarPosition.darkness(latitude: place.latitude, longitude: place.longitude, at: $0) == .dark
        } ? .dark : .twilight
        let brightSamples = times.filter {
            MoonPosition.state(latitude: place.latitude, longitude: place.longitude, at: $0).isBright
        }.count
        let moonBright = !times.isEmpty && Double(brightSamples) >= Double(times.count) / 2
        let (condition, mean) = cloudCondition(clouds, from: from, to: to)

        var outlook = NightOutlook(
            which: which, night: night, availability: .unavailable, watchLevel: watchLevel, moon: moonBright,
            darkness: darkness, clouds: condition, meanCloudPercent: mean,
            kpFetchedAt: kp?.fetchedAt, cloudsFetchedAt: clouds?.fetchedAt)
        guard let forecastKp else { return outlook }

        // §4 Level and reason.
        let nightKp = max(forecastKp, watchKp ?? 0)
        let activity = activity(kp: nightKp, band: band)
        let chance = ChanceCalculator.chance(activity: activity, darkness: darkness, moonBright: moonBright, clouds: condition)
        let reason = ChanceCalculator.reason(for: chance, activity: activity, clouds: condition)
        let watchDecided = activity != Self.activity(kp: forecastKp, band: band)
        outlook.availability = .available
        outlook.activity = activity
        outlook.maxKp = nightKp
        outlook.chance = chance
        outlook.reason = watchDecided && (reason == .someActivity || reason == .goodConditions) ? .stormWatch : .chance(reason)
        return outlook
    }

    /// The mean of the hourly forecast over the UTC hours that overlap `from ..< to`, in octas;
    /// unknown when fewer than half of those hours have a value.
    static func cloudCondition(_ clouds: CloudForecast?, from: Date, to: Date) -> (CloudCondition, Double?) {
        guard let clouds else { return (.unknown, nil) }
        let firstHour = (from.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600
        let hours = stride(from: firstHour, to: to.timeIntervalSince1970, by: 3_600).map(Date.init(timeIntervalSince1970:))
        let values = hours.compactMap { clouds.hourly[$0] }
        guard !hours.isEmpty, Double(values.count) >= Double(hours.count) / 2 else { return (.unknown, nil) }
        let mean = values.reduce(0, +) / Double(values.count)
        let octas = Int((mean * 8 / 100).rounded())
        return (ChanceCalculator.cloudCondition(octas: octas), mean)
    }
}
