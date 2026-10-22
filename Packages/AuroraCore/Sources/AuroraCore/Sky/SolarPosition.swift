import Foundation

/// Sun elevation from the NOAA solar position algorithm (research.md R6).
public enum SolarPosition {
    /// Geometric sun elevation in degrees (no atmospheric refraction).
    public static func elevation(latitude: Double, longitude: Double, at date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525

        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(radians(meanAnomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * t)
            + sin(radians(3 * meanAnomaly)) * 0.000289
        let omega = 125.04 - 1_934.136 * t
        let apparentLongitude = meanLongitude + center - 0.00569 - 0.00478 * sin(radians(omega))
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(radians(omega))
        let declination = asin(sin(radians(obliquity)) * sin(radians(apparentLongitude)))

        let y = pow(tan(radians(obliquity / 2)), 2)
        let l0 = radians(meanLongitude), m = radians(meanAnomaly)
        let equationOfTimeMinutes = 4 * degrees(
            y * sin(2 * l0) - 2 * eccentricity * sin(m) + 4 * eccentricity * y * sin(m) * cos(2 * l0)
                - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m))

        let utcMinutes = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) / 60
        var trueSolarMinutes = (utcMinutes + equationOfTimeMinutes + 4 * longitude)
            .truncatingRemainder(dividingBy: 1_440)
        if trueSolarMinutes < 0 { trueSolarMinutes += 1_440 }
        let hourAngle = radians(trueSolarMinutes / 4 - 180)

        let lat = radians(latitude)
        let cosZenith = sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)
        return 90 - degrees(acos(min(1, max(-1, cosZenith))))
    }

    public static func darkness(latitude: Double, longitude: Double, at date: Date) -> Darkness {
        darkness(elevation: elevation(latitude: latitude, longitude: longitude, at: date))
    }

    /// Above −6° too light, −12° up to −6° twilight, −12° and below dark.
    static func darkness(elevation: Double) -> Darkness {
        if elevation > -6 { return .tooLight }
        if elevation > -12 { return .twilight }
        return .dark
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
