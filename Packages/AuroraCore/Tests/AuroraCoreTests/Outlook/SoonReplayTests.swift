import Foundation
import Testing
@testable import AuroraCore

/// Recorded nights replayed through the soon rule (SC-003, research R6). The nights, their
/// solar wind (NASA OMNI 1-minute data as the propagated product would have given it) and the
/// minute each band's FMI activity rose to Probable were written by tools/calibrate-soon.py.
@Suite("Soon replay of recorded nights (SC-003)")
struct SoonReplayTests {
    struct RecordedNight: Decodable, Sendable {
        let night: String
        let kind: String
        let start: Date
        let end: Date
        let onset: [String: Date?]
    }

    /// The propagated product runs about 8 minutes behind and holds the last hour.
    static let latency: TimeInterval = 8 * 60
    static let step: TimeInterval = 5 * 60
    /// The bands' stations at which darkness is judged on quiet nights.
    static let referenceStation: [Band: Coordinate] = [
        .north: Coordinate(latitude: 68.022, longitude: 23.520),
        .central: Coordinate(latitude: 64.511, longitude: 27.227),
        .south: Coordinate(latitude: 58.264, longitude: 26.460),
    ]

    static let nights: [RecordedNight] = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecordedNight].self, from: Fixtures.data("outlook/soon-nights/nights.json"))) ?? []
    }()

    static func samples(_ night: RecordedNight) throws -> [SolarWindSample] {
        String(decoding: try Fixtures.data("outlook/soon-nights/\(night.night).csv"), as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map { line in
                let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                return SolarWindSample(time: UTCTime.parse(f[0])!, arrival: UTCTime.parse(f[1]),
                                       bz: Double(f[2]), speed: Double(f[3]), density: Double(f[4]))
            }
    }

    /// The state every 5 minutes, as the app would have refreshed it.
    static func replay(_ night: RecordedNight, band: Band) throws -> [(time: Date, state: SoonState)] {
        let samples = try samples(night)
        var states: [(Date, SoonState)] = []
        var previous: SoonState?
        for now in stride(from: night.start.timeIntervalSince1970, through: night.end.timeIntervalSince1970, by: step) {
            let date = Date(timeIntervalSince1970: now)
            let published = samples.filter { $0.time <= date - latency && $0.time >= date - 3_600 }
            let signal = SoonCalculator.signal(samples: published, band: band, now: date, previous: previous)
            states.append((date, signal.state))
            previous = signal.state == .unknown ? nil : signal.state
        }
        return states
    }

    @Test func enoughRecordedNights() {
        #expect(Self.nights.filter { $0.kind == "storm" && $0.onset["north"].flatMap { $0 } != nil }.count >= 20)
        #expect(Self.nights.filter { $0.kind == "quiet" }.count >= 20)
    }

    /// Possible or Likely at some refresh from 75 to 15 minutes before the rise, in ≥ 70% of storm
    /// nights. Rises on quiet nights are not part of the set (research R6).
    @Test(arguments: Band.allCases)
    func risesAreSeenComing(band: Band) throws {
        let storms = Self.nights.filter { $0.kind == "storm" }
            .compactMap { night in night.onset[band.rawValue].flatMap { $0 }.map { (night, $0) } }
        var seen = 0
        for (night, onset) in storms {
            let states = try Self.replay(night, band: band)
            if states.contains(where: { $0.time >= onset - 75 * 60 && $0.time <= onset - 15 * 60 && ($0.state == .possible || $0.state == .likely) }) {
                seen += 1
            }
        }
        #expect(storms.count >= 8)
        #expect(Double(seen) >= 0.7 * Double(storms.count), "\(band): \(seen) of \(storms.count)")
    }

    /// Likely for at most 10% of the dark refreshes of quiet nights.
    @Test(arguments: Band.allCases)
    func quietNightsAreRarelyLikely(band: Band) throws {
        let place = try #require(Self.referenceStation[band])
        var dark = 0, likely = 0
        for night in Self.nights where night.kind == "quiet" {
            for (time, state) in try Self.replay(night, band: band)
            where SolarPosition.darkness(latitude: place.latitude, longitude: place.longitude, at: time) == .dark {
                dark += 1
                if state == .likely { likely += 1 }
            }
        }
        #expect(dark > 0)
        #expect(Double(likely) <= 0.1 * Double(dark), "\(band): \(likely) of \(dark)")
    }
}
