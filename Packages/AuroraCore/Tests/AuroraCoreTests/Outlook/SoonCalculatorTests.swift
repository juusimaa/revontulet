import Foundation
import Testing
@testable import AuroraCore

@Suite("Soon rules (contracts/soon-rules.md)")
struct SoonCalculatorTests {
    static let now = utc("2026-11-09T20:00:00Z")

    /// 20 one-minute samples, the newest observed `age` minutes before now; `minute(i)` gives Bz and
    /// speed for the i-th minute from the oldest; each arrives `arrival` minutes after observation.
    static func window(
        age: Double = 8, arrival: Double = 55, count: Int = 20,
        _ minute: (Int) -> (bz: Double?, speed: Double?)
    ) -> [SolarWindSample] {
        (0..<count).map { i in
            let observed = now.addingTimeInterval(-(age + Double(count - 1 - i)) * 60)
            let (bz, speed) = minute(i)
            return SolarWindSample(time: observed, arrival: observed.addingTimeInterval(arrival * 60),
                                   bz: bz, speed: speed, density: 4.2)
        }
    }

    static func steady(bz: Double, speed: Double, age: Double = 8, arrival: Double = 55) -> [SolarWindSample] {
        window(age: age, arrival: arrival) { _ in (bz, speed) }
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let number: Int
        let samples: [SolarWindSample]
        var band: Band = .north
        var previous: SoonState?
        let state: SoonState
        let arrivalMinutes: Int?

        var testDescription: String { "case \(number)" }
    }

    /// Reference cases 1–12: band North, no previous state, newest sample 8 minutes old, 20 valid
    /// minutes, arrival 55 minutes after observation, unless stated.
    static let referenceCases: [Case] = [
        // Driver 1.8 mV/m.
        Case(number: 1, samples: steady(bz: -4, speed: 450), state: .possible, arrivalMinutes: 30),
        Case(number: 2, samples: steady(bz: -8, speed: 500), state: .likely, arrivalMinutes: 30),
        Case(number: 3, samples: steady(bz: 5, speed: 450), state: .quiet, arrivalMinutes: nil),
        Case(number: 4, samples: window { $0 < 5 ? (-20, 450) : (3, 450) }, state: .quiet, arrivalMinutes: nil),
        Case(number: 5, samples: window { $0 < 9 ? (2, 500) : (-8, 500) }, state: .likely, arrivalMinutes: 30),
        Case(number: 6, samples: steady(bz: -8, speed: 500, age: 21), state: .unknown, arrivalMinutes: nil),
        Case(number: 7, samples: window { $0 < 6 ? (nil, 500) : (-8, 500) }, state: .unknown, arrivalMinutes: nil),
        Case(number: 8, samples: steady(bz: -8, speed: 500), band: .south, state: .possible, arrivalMinutes: 30),
        // Driver 2.4 mV/m: 400 km/s, Bz −6.
        Case(number: 9, samples: steady(bz: -6, speed: 400), previous: .likely, state: .likely, arrivalMinutes: 30),
        // Driver 1.6 mV/m: 400 km/s, Bz −4.
        Case(number: 10, samples: steady(bz: -4, speed: 400), previous: .likely, state: .possible, arrivalMinutes: 30),
        Case(number: 11, samples: steady(bz: -8, speed: 500, arrival: 30), state: .likely, arrivalMinutes: 15),
        Case(number: 12, samples: steady(bz: -8, speed: 500, arrival: 80), state: .likely, arrivalMinutes: 60),
    ]

    @Test(arguments: referenceCases)
    func referenceCase(_ c: Case) {
        let signal = SoonCalculator.signal(samples: c.samples, band: c.band, now: Self.now, previous: c.previous)

        #expect(signal.state == c.state)
        #expect(signal.arrivalMinutes == c.arrivalMinutes)
    }

    @Test func driverIsTheMedianEy() throws {
        let signal = SoonCalculator.signal(samples: Self.steady(bz: -8, speed: 500), band: .north, now: Self.now, previous: nil)
        #expect(try #require(signal.driver) == 4.0)

        // Case 5: 9 minutes at 0 and 11 at 4.0; the median of 20 is the mean of the middle two.
        let mixed = SoonCalculator.signal(
            samples: Self.window { $0 < 9 ? (2, 500) : (-8, 500) }, band: .north, now: Self.now, previous: nil)
        #expect(mixed.driver == 4.0)
    }

    @Test func latestAndDataTimeAreTheNewestCompleteSample() {
        var samples = Self.steady(bz: -8, speed: 500)
        // A newer minute without speed does not count.
        samples.append(SolarWindSample(time: Self.now.addingTimeInterval(-7 * 60), arrival: nil, bz: -9, speed: nil, density: nil))
        let signal = SoonCalculator.signal(samples: samples, band: .north, now: Self.now, previous: nil)

        #expect(signal.latest == samples[19])
        #expect(signal.dataTime == Self.now.addingTimeInterval(-8 * 60))
    }

    @Test func unknownStillCarriesTheLastDataTime() {
        let signal = SoonCalculator.signal(
            samples: Self.steady(bz: -8, speed: 500, age: 45), band: .north, now: Self.now, previous: nil)

        #expect(signal.state == .unknown)
        #expect(signal.driver == nil)
        #expect(signal.dataTime == Self.now.addingTimeInterval(-45 * 60))
    }

    @Test func noSamplesIsUnknown() {
        let signal = SoonCalculator.signal(samples: [], band: .central, now: Self.now, previous: .likely)
        #expect(signal == SoonSignal(state: .unknown))
    }

    @Test func unsortedSamplesGiveTheSameSignal() {
        let samples = Self.window { $0 < 9 ? (2, 500) : (-8, 500) }
        #expect(SoonCalculator.signal(samples: samples.reversed(), band: .north, now: Self.now, previous: nil)
            == SoonCalculator.signal(samples: samples, band: .north, now: Self.now, previous: nil))
    }

    // MARK: Main-screen visibility (FR-010)

    /// Kevo on midsummer night: too light now and an hour later.
    @Test func hiddenWhenTooLightNowAndAtArrival() {
        let kevo = Coordinate(latitude: 69.756, longitude: 27.007)
        let midsummer = utc("2026-06-21T22:00:00Z")
        let signal = SoonSignal(state: .likely, driver: 4, arrivalMinutes: 60)

        #expect(!SoonCalculator.showsOnMainScreen(signal, at: kevo, now: midsummer))
    }

    /// Oulu at 16:30 local in late October: still light now, but dark in 45 minutes.
    @Test func shownWhenItGetsDarkBeforeArrival() {
        let oulu = Coordinate(latitude: 65.01, longitude: 25.47)
        let dusk = utc("2026-10-30T14:20:00Z")
        #expect(SolarPosition.darkness(latitude: 65.01, longitude: 25.47, at: dusk) == .tooLight)
        #expect(SolarPosition.darkness(latitude: 65.01, longitude: 25.47, at: dusk + 45 * 60) != .tooLight)

        #expect(SoonCalculator.showsOnMainScreen(SoonSignal(state: .possible, driver: 2, arrivalMinutes: 45), at: oulu, now: dusk))
        #expect(!SoonCalculator.showsOnMainScreen(SoonSignal(state: .possible, driver: 2, arrivalMinutes: 15), at: oulu, now: dusk))
    }

    /// Light does not depend on clouds: an overcast dark night still shows the line.
    @Test func shownOnADarkNightAndNeverForQuietOrUnknown() {
        let oulu = Coordinate(latitude: 65.01, longitude: 25.47)
        let night = utc("2026-11-09T21:00:00Z")

        #expect(SoonCalculator.showsOnMainScreen(SoonSignal(state: .likely, driver: 4, arrivalMinutes: 30), at: oulu, now: night))
        #expect(!SoonCalculator.showsOnMainScreen(SoonSignal(state: .quiet, driver: 0), at: oulu, now: night))
        #expect(!SoonCalculator.showsOnMainScreen(.unknown, at: oulu, now: night))
    }
}
