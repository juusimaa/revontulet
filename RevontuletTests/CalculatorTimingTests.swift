import AuroraCore
import Foundation
import Testing

/// The plan's performance goal (T075): `OutlookCalculator` plus `SoonCalculator` in under 50 ms.
/// Runs wherever the app tests run; run on a device to measure it there:
/// `xcodebuild test -scheme Revontulet -only-testing:RevontuletTests/CalculatorTimingTests
/// -destination 'platform=iOS,id=<device id>'`.
@Suite("Calculator timing")
struct CalculatorTimingTests {
    static let oulu = Coordinate(latitude: 65.01, longitude: 25.47)
    /// 19:00 in Finland on a full-moon night: tonight is under way and the moon is up, so every
    /// sky and moon sample is computed.
    static let now = Date(timeIntervalSince1970: 1_795_539_600)  // 2026-11-24T17:00:00Z
    static let hour: TimeInterval = 3_600

    /// Sized like the live products: 81 Kp blocks (6.5 days back, 2.5 ahead), 66 hours of one
    /// zone's cloud forecast, a two-day G1 watch and one hour of minute solar wind.
    static let kp = KpForecast(
        blocks: (0..<81).map { i in
            let start = now - 156 * hour + Double(i) * 3 * hour
            return KpBlock(start: start, kp: Double(i % 7), kind: start < now ? .observed : .predicted)
        },
        fetchedAt: now)
    static let watches = [StormWatch(level: 1, days: ["2026-11-24", "2026-11-25"], issuedAt: now - 20 * hour)]
    static let clouds = CloudForecast(
        zoneID: "OUJ",
        hourly: Dictionary(uniqueKeysWithValues: (0..<66).map { (now + Double($0) * hour, Double($0 * 13 % 100)) }),
        fetchedAt: now)
    static let samples = (0..<60).map { minute in
        let time = now - 60 * 60 + Double(minute) * 60
        return SolarWindSample(time: time, arrival: time + 45 * 60, bz: -Double(minute % 12), speed: 450 + Double(minute),
                               density: 5)
    }

    @Test func outlookAndSoonTakeUnder50ms() throws {
        let clock = ContinuousClock()
        // The first run counts too: after a cold launch it is the one the user waits for.
        let runs = (0..<5).map { _ in
            clock.measure {
                let outlook = OutlookCalculator.outlook(place: Self.oulu, band: .central, now: Self.now, kp: Self.kp,
                                                        watches: Self.watches, clouds: Self.clouds)
                var soon = SoonCalculator.signal(samples: Self.samples, band: .central, now: Self.now, previous: nil)
                soon.showsOnMainScreen = SoonCalculator.showsOnMainScreen(soon, at: Self.oulu, now: Self.now)
                #expect(outlook.tonight.availability == .available)
                #expect(soon.state != .unknown)
            }
        }
        let milliseconds = runs.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1e3 }
        print("Calculator timing (ms):", milliseconds.map { String(format: "%.2f", $0) }.joined(separator: ", "))
        let slowest = try #require(runs.max())
        #expect(slowest < .milliseconds(50), "slowest run \(slowest)")
    }
}
