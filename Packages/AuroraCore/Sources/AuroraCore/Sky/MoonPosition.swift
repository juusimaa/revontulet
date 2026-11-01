import Foundation

/// The moon's phase name: eight equal sectors of the cycle, each centred on its nominal phase.
public enum MoonPhase: String, Sendable, Hashable, Codable, CaseIterable {
    case new
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case full
    case waningGibbous
    case lastQuarter
    case waningCrescent

    /// Localisation key, e.g. `moon.phase.full`.
    public var key: String { "moon.phase.\(rawValue)" }
}

/// Where the moon is in the sky at a place, and how much of it is lit.
public struct MoonState: Sendable, Hashable, Codable {
    /// Topocentric altitude of the centre in degrees, without refraction.
    public var altitude: Double
    /// 0…1.
    public var illuminatedFraction: Double
    public var phase: MoonPhase
    /// Up and at least half lit (chance-rules v2).
    public var isBright: Bool

    public init(altitude: Double, illuminatedFraction: Double, phase: MoonPhase, isBright: Bool) {
        self.altitude = altitude
        self.illuminatedFraction = illuminatedFraction
        self.phase = phase
        self.isBright = isBright
    }
}

/// Moon position and phase from Meeus, *Astronomical Algorithms* (2nd ed.), chapters 47 and 48,
/// with the largest periodic terms (research R4). Accurate to about 0.1°.
public enum MoonPosition {
    public static func state(latitude: Double, longitude: Double, at date: Date) -> MoonState {
        let t = SolarPosition.julianCenturies(date)
        let moon = ecliptic(t)

        // Equatorial coordinates, then the local hour angle.
        let epsilon = rad(SolarPosition.obliquity(t))
        let lambda = rad(moon.longitude), beta = rad(moon.latitude)
        let rightAscension = deg(atan2(sin(lambda) * cos(epsilon) - tan(beta) * sin(epsilon), cos(lambda)))
        let declination = deg(asin(sin(beta) * cos(epsilon) + cos(beta) * sin(epsilon) * sin(lambda)))
        let hourAngle = SolarPosition.localSiderealTime(date, longitude: longitude) - rightAscension
        let geocentric = SolarPosition.altitude(declination: declination, hourAngle: hourAngle, latitude: latitude)

        // Parallax: seen from the surface the moon is lower by up to about 1°.
        let parallax = asin(earthRadiusKm / moon.distanceKm)
        let altitude = geocentric - deg(asin(sin(parallax) * cos(rad(geocentric))))

        // Illuminated fraction from the elongation between sun and moon (ch. 48).
        let sunLongitude = SolarPosition.sunApparentLongitude(t)
        let elongation = acos(cos(beta) * cos(lambda - rad(sunLongitude)))
        let phaseAngle = atan2(sunDistanceKm * sin(elongation), moon.distanceKm - sunDistanceKm * cos(elongation))
        let fraction = (1 + cos(phaseAngle)) / 2

        let age = normalized(moon.longitude - sunLongitude)
        let phase = MoonPhase.allCases[Int(normalized(age + 22.5) / 45) % 8]

        return MoonState(
            altitude: altitude, illuminatedFraction: fraction, phase: phase,
            isBright: altitude > 0 && fraction >= 0.5)
    }

    static let earthRadiusKm = 6_378.14
    static let sunDistanceKm = 149_597_870.7

    /// Geocentric apparent ecliptic longitude and latitude (degrees) and distance (km), ch. 47.
    static func ecliptic(_ t: Double) -> (longitude: Double, latitude: Double, distanceKm: Double) {
        let meanLongitude = 218.3164477 + t * (481_267.88123421 + t * (-0.0015786 + t * (1 / 538_841.0 - t / 65_194_000)))
        let d = 297.8501921 + t * (445_267.1114034 + t * (-0.0018819 + t * (1 / 545_868.0 - t / 113_065_000)))
        let m = 357.5291092 + t * (35_999.0502909 + t * (-0.0001536 + t / 24_490_000))
        let mPrime = 134.9633964 + t * (477_198.8675055 + t * (0.0087414 + t * (1 / 69_699.0 - t / 14_712_000)))
        let f = 93.2720950 + t * (483_202.0175233 + t * (-0.0036539 + t * (-1 / 3_526_000.0 + t / 863_310_000)))
        let a1 = 119.75 + 131.849 * t
        let a2 = 53.09 + 479_264.290 * t
        let a3 = 313.45 + 481_266.484 * t
        let e = 1 - t * (0.002516 + 0.0000074 * t)

        func argument(_ term: (d: Double, m: Double, mPrime: Double, f: Double)) -> Double {
            rad(term.d * d + term.m * m + term.mPrime * mPrime + term.f * f)
        }
        func eccentricity(_ m: Double) -> Double { abs(m) == 2 ? e * e : abs(m) == 1 ? e : 1 }

        var sumL = 0.0, sumR = 0.0, sumB = 0.0
        for term in longitudeTerms {
            let x = argument((term.d, term.m, term.mPrime, term.f))
            sumL += term.l * eccentricity(term.m) * sin(x)
            sumR += term.r * eccentricity(term.m) * cos(x)
        }
        for term in latitudeTerms {
            sumB += term.b * eccentricity(term.m) * sin(argument((term.d, term.m, term.mPrime, term.f)))
        }
        sumL += 3_958 * sin(rad(a1)) + 1_962 * sin(rad(meanLongitude - f)) + 318 * sin(rad(a2))
        sumB += -2_235 * sin(rad(meanLongitude)) + 382 * sin(rad(a3)) + 175 * sin(rad(a1 - f))
            + 175 * sin(rad(a1 + f)) + 127 * sin(rad(meanLongitude - mPrime)) - 115 * sin(rad(meanLongitude + mPrime))

        // Nutation in longitude, as for the sun's apparent longitude.
        let nutation = -0.00478 * sin(rad(SolarPosition.omega(t)))
        return (normalized(meanLongitude + sumL / 1_000_000 + nutation), sumB / 1_000_000, 385_000.56 + sumR / 1_000)
    }

    /// Meeus table 47.A, largest terms: multiples of D, M, M′, F; longitude (1e-6°); distance (1e-3 km).
    private static let longitudeTerms: [(d: Double, m: Double, mPrime: Double, f: Double, l: Double, r: Double)] = [
        (0, 0, 1, 0, 6_288_774, -20_905_355),
        (2, 0, -1, 0, 1_274_027, -3_699_111),
        (2, 0, 0, 0, 658_314, -2_955_968),
        (0, 0, 2, 0, 213_618, -569_925),
        (0, 1, 0, 0, -185_116, 48_888),
        (0, 0, 0, 2, -114_332, -3_149),
        (2, 0, -2, 0, 58_793, 246_158),
        (2, -1, -1, 0, 57_066, -152_138),
        (2, 0, 1, 0, 53_322, -170_733),
        (2, -1, 0, 0, 45_758, -204_586),
        (0, 1, -1, 0, -40_923, -129_620),
        (1, 0, 0, 0, -34_720, 108_743),
        (0, 1, 1, 0, -30_383, 104_755),
        (2, 0, 0, -2, 15_327, 10_321),
        (0, 0, 1, 2, -12_528, 0),
        (0, 0, 1, -2, 10_980, 79_661),
        (4, 0, -1, 0, 10_675, -34_782),
        (0, 0, 3, 0, 10_034, -23_210),
        (4, 0, -2, 0, 8_548, -21_636),
        (2, 1, -1, 0, -7_888, 24_208),
        (2, 1, 0, 0, -6_766, 30_824),
        (1, 0, -1, 0, -5_163, -8_379),
        (1, 1, 0, 0, 4_987, -16_675),
        (2, -1, 1, 0, 4_036, -12_831),
        (2, 0, 2, 0, 3_994, -10_445),
        (4, 0, 0, 0, 3_861, -11_650),
        (2, 0, -3, 0, 3_665, 14_403),
        (0, 1, -2, 0, -2_689, -7_003),
        (2, 0, -1, 2, -2_602, 0),
        (2, -1, -2, 0, 2_390, 10_056),
        (1, 0, 1, 0, -2_348, 6_322),
        (2, -2, 0, 0, 2_236, -9_884),
        (0, 1, 2, 0, -2_120, 5_751),
        (0, 2, 0, 0, -2_069, 0),
        (2, -2, -1, 0, 2_048, -4_950),
        (2, 0, 1, -2, -1_773, 4_130),
        (2, 0, 0, 2, -1_595, 0),
        (4, -1, -1, 0, 1_215, -3_958),
        (0, 0, 2, 2, -1_110, 0),
        (3, 0, -1, 0, -892, 3_258),
    ]

    /// Meeus table 47.B, largest terms: multiples of D, M, M′, F; latitude (1e-6°).
    private static let latitudeTerms: [(d: Double, m: Double, mPrime: Double, f: Double, b: Double)] = [
        (0, 0, 0, 1, 5_128_122),
        (0, 0, 1, 1, 280_602),
        (0, 0, 1, -1, 277_693),
        (2, 0, 0, -1, 173_237),
        (2, 0, -1, 1, 55_413),
        (2, 0, -1, -1, 46_271),
        (2, 0, 0, 1, 32_573),
        (0, 0, 2, 1, 17_198),
        (2, 0, 1, -1, 9_266),
        (0, 0, 2, -1, 8_822),
        (2, -1, 0, -1, 8_216),
        (2, 0, -2, -1, 4_324),
        (2, 0, 1, 1, 4_200),
        (2, 1, 0, -1, -3_359),
        (2, -1, -1, 1, 2_463),
        (2, -1, 0, 1, 2_211),
        (2, -1, -1, -1, 2_065),
        (0, 1, -1, -1, -1_870),
        (4, 0, -1, -1, 1_828),
        (0, 1, 0, 1, -1_794),
        (0, 0, 0, 3, -1_749),
        (0, 1, -1, 1, -1_565),
        (1, 0, 0, 1, -1_491),
        (0, 1, 1, 1, -1_475),
        (0, 1, 1, -1, -1_410),
        (0, 1, 0, -1, -1_344),
        (1, 0, 0, -1, -1_335),
    ]

    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func rad(_ degrees: Double) -> Double { SolarPosition.radians(degrees) }
    private static func deg(_ radians: Double) -> Double { SolarPosition.degrees(radians) }
}
