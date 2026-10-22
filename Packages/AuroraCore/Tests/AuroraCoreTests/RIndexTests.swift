import Foundation
import Testing
@testable import AuroraCore

/// FMI's published R values for the recorded magnetometer data. The file comes from FMI's chart
/// endpoint, which is not open data, so it is kept local only; regenerate it with
/// `tools/record-fixtures.py`.
private let referenceFileExists = Fixtures.exists("reference-r.json")

private struct ReferenceR: Decodable {
    let station: String
    let time: String
    let r: Double
}

@Suite("R value")
struct RIndexTests {
    private func reference() throws -> [ReferenceR] {
        try JSONDecoder().decode([ReferenceR].self, from: Fixtures.data("reference-r.json"))
    }

    @Test(
        "Computed R is within ±3 of FMI's published value (FR-002)",
        .enabled(if: referenceFileExists, "reference-r.json is missing; run tools/record-fixtures.py"))
    func matchesFMIWithinTolerance() throws {
        let samples = try MagnetometerFixtures.samplesByStation()
        let reference = try reference()
        #expect(reference.count >= 100)

        for point in reference {
            let stationSamples = try #require(samples[point.station], "\(point.station)")
            let r = try #require(RIndex.compute(samples: stationSamples, end: utc(point.time)),
                                 "\(point.station) \(point.time)")
            #expect(abs(r - point.r) <= 3, "\(point.station) \(point.time): \(r) vs FMI \(point.r)")
        }
    }

    @Test(
        "Activity level matches FMI away from thresholds (SC-003)",
        .enabled(if: referenceFileExists, "reference-r.json is missing; run tools/record-fixtures.py"))
    func activityLevelMatchesFMI() throws {
        let samples = try MagnetometerFixtures.samplesByStation()
        let stations = Dictionary(uniqueKeysWithValues: try ReferenceData.loadStations().map { ($0.id, $0) })

        var compared = 0
        for point in try reference() {
            let station = try #require(stations[point.station])
            let nearThreshold = abs(point.r - station.yellowThreshold) <= 3 || abs(point.r - station.redThreshold) <= 3
            if nearThreshold { continue }
            let r = try #require(RIndex.compute(samples: samples[point.station] ?? [], end: utc(point.time)))
            #expect(ActivityClassifier.level(r: r, station: station)
                    == ActivityClassifier.level(r: point.r, station: station),
                    "\(point.station) \(point.time): \(r) vs FMI \(point.r)")
            compared += 1
        }
        #expect(compared >= 20)
    }

    @Test func windowUsesSixtyOneSamplesEndingTenSecondsBeforeEnd() {
        let end = utc("2026-10-22T12:00:00Z")
        // A constant field with one 100 nT step in X within the newest half of the window, and a
        // sample just outside the window that must not count.
        let samples = (0...62).map { i in
            let time = end.addingTimeInterval(Double(-10 * i))
            return MagnetometerSample(stationID: "T", time: time, x: i <= 5 || i == 62 ? 100 : 0, y: 0, z: 0)
        }
        let r = RIndex.compute(samples: samples, end: end)
        // One newest-half difference of 100 nT with weight 2, over a weight sum of 30·2 + 30·1 = 90.
        #expect(r.map { abs($0 - (RIndex.scale * 200 / 90 - RIndex.offset)) < 1e-9 } == true)
    }

    @Test func tooManyMissingSamplesGiveNoValue() {
        let end = utc("2026-10-22T12:00:00Z")
        func samples(missing: Int) -> [MagnetometerSample] {
            (1...61).map { i in
                let time = end.addingTimeInterval(Double(-10 * i))
                return MagnetometerSample(stationID: "T", time: time, x: i <= missing ? nil : 5, y: 1, z: 2)
            }
        }
        #expect(RIndex.compute(samples: samples(missing: 3), end: end) != nil)
        #expect(RIndex.compute(samples: samples(missing: 4), end: end) == nil)

        // Samples absent from the input count as missing too.
        #expect(RIndex.compute(samples: Array(samples(missing: 0).dropFirst(4)), end: end) == nil)
        #expect(RIndex.compute(samples: [], end: end) == nil)
    }

    @Test func quietFieldIsClampedToZero() {
        let end = utc("2026-10-22T12:00:00Z")
        let samples = (1...61).map {
            MagnetometerSample(stationID: "T", time: end.addingTimeInterval(Double(-10 * $0)), x: 3, y: 4, z: 5)
        }
        #expect(RIndex.compute(samples: samples, end: end) == 0)
    }
}
