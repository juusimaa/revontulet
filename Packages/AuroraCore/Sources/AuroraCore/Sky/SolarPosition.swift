import Foundation

/// Sun elevation from the NOAA solar position algorithm (research.md R6).
public enum SolarPosition {
    /// Geometric sun elevation in degrees (no atmospheric refraction).
    public static func elevation(latitude: Double, longitude: Double, at date: Date) -> Double {
        let t = julianCenturies(date)

        let meanLongitude = sunMeanLongitude(t)
        let meanAnomaly = sunMeanAnomaly(t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let obliquity = obliquity(t)
        let declination = asin(sin(radians(obliquity)) * sin(radians(sunApparentLongitude(t))))

        let y = pow(tan(radians(obliquity / 2)), 2)
        let l0 = radians(meanLongitude), m = radians(meanAnomaly)
        let equationOfTimeMinutes = 4 * degrees(
            y * sin(2 * l0) - 2 * eccentricity * sin(m) + 4 * eccentricity * y * sin(m) * cos(2 * l0)
                - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m))

        let utcMinutes = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) / 60
        var trueSolarMinutes = (utcMinutes + equationOfTimeMinutes + 4 * longitude)
            .truncatingRemainder(dividingBy: 1_440)
        if trueSolarMinutes < 0 { trueSolarMinutes += 1_440 }
        let hourAngle = trueSolarMinutes / 4 - 180

        return altitude(declination: degrees(declination), hourAngle: hourAngle, latitude: latitude)
    }

    public static func darkness(latitude: Double, longitude: Double, at date: Date) -> Darkness {
        darkness(elevation: elevation(latitude: latitude, longitude: longitude, at: date))
    }

    /// The first time within the next 24 hours, in 5-minute steps, when it is no longer too light.
    /// nil when the sky stays too light all that time, e.g. near midsummer in Lapland.
    public static func nextDarkness(latitude: Double, longitude: Double, after date: Date) -> Date? {
        let step: TimeInterval = 5 * 60
        for index in 1...288 {
            let candidate = date.addingTimeInterval(Double(index) * step)
            if darkness(latitude: latitude, longitude: longitude, at: candidate) != .tooLight { return candidate }
        }
        return nil
    }

    /// Above −6° too light, −12° up to −6° twilight, −12° and below dark.
    static func darkness(elevation: Double) -> Darkness {
        if elevation > -6 { return .tooLight }
        if elevation > -12 { return .twilight }
        return .dark
    }

    // MARK: Shared with MoonPosition (research R4)

    static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    /// Julian centuries since J2000.0.
    static func julianCenturies(_ date: Date) -> Double {
        (julianDay(date) - 2_451_545) / 36_525
    }

    static func sunMeanLongitude(_ t: Double) -> Double {
        (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
    }

    static func sunMeanAnomaly(_ t: Double) -> Double {
        357.52911 + t * (35_999.05029 - 0.0001537 * t)
    }

    /// Longitude of the Moon's ascending node, used for the nutation corrections.
    static func omega(_ t: Double) -> Double {
        125.04 - 1_934.136 * t
    }

    /// The sun's apparent ecliptic longitude in degrees.
    static func sunApparentLongitude(_ t: Double) -> Double {
        let meanAnomaly = sunMeanAnomaly(t)
        let center = sin(radians(meanAnomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * t)
            + sin(radians(3 * meanAnomaly)) * 0.000289
        return sunMeanLongitude(t) + center - 0.00569 - 0.00478 * sin(radians(omega(t)))
    }

    static func meanObliquity(_ t: Double) -> Double {
        23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
    }

    /// Obliquity corrected for nutation, in degrees.
    static func obliquity(_ t: Double) -> Double {
        meanObliquity(t) + 0.00256 * cos(radians(omega(t)))
    }

    /// Local mean sidereal time in degrees (east longitude positive).
    static func localSiderealTime(_ date: Date, longitude: Double) -> Double {
        let d = julianDay(date) - 2_451_545
        let t = d / 36_525
        let greenwich = 280.46061837 + 360.98564736629 * d + t * t * (0.000387933 - t / 38_710_000)
        return (greenwich + longitude).truncatingRemainder(dividingBy: 360)
    }

    /// Altitude in degrees of a body at `declination` and local `hourAngle` (both degrees).
    static func altitude(declination: Double, hourAngle: Double, latitude: Double) -> Double {
        let lat = radians(latitude), dec = radians(declination)
        let sinAltitude = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(radians(hourAngle))
        return 90 - degrees(acos(min(1, max(-1, sinAltitude))))
    }

    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
