import Foundation
import Testing
@testable import AuroraCore

@Suite("Station selection")
struct StationSelectionTests {
    private let stations = Dictionary(uniqueKeysWithValues: try! ReferenceData.loadStations().map { ($0.id, $0) })
    private let measuredAt = utc("2026-10-22T16:35:00Z")
    // Rovaniemi: Ranua (~74 km) is nearest, Pello (~85 km) next.
    private let rovaniemi = Place(coordinate: Coordinate(latitude: 66.50, longitude: 25.73),
                                  municipalityCode: "698", source: .currentLocation)

    private func reading(_ id: String, r: Double?) -> StationReading {
        let station = stations[id]!
        return StationReading(station: station, r: r, measuredAt: measuredAt,
                              activity: r.map { ActivityClassifier.level(r: $0, station: station) })
    }

    @Test func nearestStationWithValidR() throws {
        let readings = ["KEV", "PEL", "RAN", "HAN"].map { reading($0, r: 10) }

        let selection = try #require(StationSelector.select(for: rovaniemi, readings: readings, previous: nil))

        #expect(selection.reading.station.id == "RAN")
        #expect(abs(selection.distanceKm - 74) < 3)
        #expect(!selection.usedMoreDistantStation)
    }

    @Test func fallsBackWhenNearestHasNoValue() throws {
        let readings = [reading("RAN", r: nil), reading("PEL", r: 20), reading("HAN", r: 30)]

        let selection = try #require(StationSelector.select(for: rovaniemi, readings: readings, previous: nil))

        #expect(selection.reading.station.id == "PEL")
        #expect(selection.usedMoreDistantStation)
    }

    @Test func noValidStationGivesNothing() {
        let readings = [reading("RAN", r: nil), reading("PEL", r: nil)]

        #expect(StationSelector.select(for: rovaniemi, readings: readings, previous: nil) == nil)
    }

    @Test func hysteresisKeepsPreviousStationUnlessAnotherIsFiveKmCloser() throws {
        // A point almost halfway between Ranua and Pello.
        let readings = [reading("RAN", r: 10), reading("PEL", r: 10)]
        func place(_ lat: Double, _ lon: Double) -> Place {
            Place(coordinate: Coordinate(latitude: lat, longitude: lon), municipalityCode: "698", source: .currentLocation)
        }
        let between = place(66.40, 25.245)
        let toRanua = Geo.distanceKm(between.coordinate, stations["RAN"]!.coordinate)
        let toPello = Geo.distanceKm(between.coordinate, stations["PEL"]!.coordinate)
        #expect(abs(toRanua - toPello) < 5, "test point must be within the hysteresis band")

        let nearest = toRanua < toPello ? "RAN" : "PEL"
        let other = nearest == "RAN" ? "PEL" : "RAN"
        #expect(try #require(StationSelector.select(for: between, readings: readings, previous: other)).reading.station.id == other)
        #expect(try #require(StationSelector.select(for: between, readings: readings, previous: nil)).reading.station.id == nearest)

        // Rovaniemi is ~11 km closer to Ranua than to Pello, so the previous Pello is dropped.
        #expect(try #require(StationSelector.select(for: rovaniemi, readings: readings, previous: "PEL")).reading.station.id == "RAN")
    }

    @Test func previousStationWithoutValueIsNotKept() throws {
        let readings = [reading("RAN", r: 10), reading("PEL", r: nil)]

        let selection = try #require(StationSelector.select(for: rovaniemi, readings: readings, previous: "PEL"))

        #expect(selection.reading.station.id == "RAN")
    }
}

@Suite("Cloud selection")
struct CloudSelectionTests {
    private let time = utc("2026-10-22T16:30:00Z")
    private let rovaniemi = Coordinate(latitude: 66.50, longitude: 25.73)

    private func observation(_ lat: Double, _ lon: Double, _ octas: Int?) -> CloudObservation {
        CloudObservation(coordinate: Coordinate(latitude: lat, longitude: lon), time: time, octas: octas)
    }

    @Test func nearestValidObservation() {
        let observations = [
            observation(66.52, 25.80, nil),   // nearest, but no value
            observation(66.60, 25.90, 7),     // ~14 km
            observation(65.00, 25.50, 0),     // ~167 km
        ]

        let cover = CloudSelector.select(for: rovaniemi, observations: observations)

        #expect(cover.condition == .overcast)
        #expect(cover.octas == 7)
        #expect(cover.source == Coordinate(latitude: 66.60, longitude: 25.90))
        #expect(cover.distanceKm.map { abs($0 - 13.6) < 1.5 } == true)
    }

    @Test func nothingWithinHundredKilometresIsUnknown() {
        let observations = [observation(65.00, 25.50, 0), observation(66.52, 25.80, nil)]

        #expect(CloudSelector.select(for: rovaniemi, observations: observations) == .unknown)
        #expect(CloudSelector.select(for: rovaniemi, observations: []) == .unknown)
    }

    @Test func recordedObservationsCoverRovaniemi() async throws {
        let name = try #require(Fixtures.first(prefix: "clouds-"))
        let http = StubHTTPClient(["fmi::observations::weather::simple": .fixture(name)])
        let observations = try await FMIClient(http: http, stations: []).cloudObservations(now: time)

        let cover = CloudSelector.select(for: rovaniemi, observations: observations)

        #expect(cover.condition != .unknown)
        #expect(cover.distanceKm.map { $0 <= 100 } == true)
    }
}
