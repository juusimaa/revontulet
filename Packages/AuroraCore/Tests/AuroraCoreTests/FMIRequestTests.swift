import Foundation
import Testing
@testable import AuroraCore

@Suite("FMI request builders")
struct FMIRequestTests {
    private let now = utc("2026-10-22T16:35:47Z")

    private func items(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.scheme == "https")
        #expect(components?.host == "opendata.fmi.fi")
        #expect(components?.path == "/wfs")
        let items = components?.queryItems ?? []
        #expect(Set(items.map(\.name)).count == items.count, "no duplicate query items")
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func magnetometerRequest() {
        let query = items(FMIRequests.magnetometer(now: now))

        #expect(query == [
            "service": "WFS",
            "version": "2.0.0",
            "request": "getFeature",
            "storedquery_id": "fmi::observations::magnetometer::simple",
            "bbox": "5,50,40,80",
            "parameters": "MAGNX_PT10S_AVG,MAGNY_PT10S_AVG,MAGNZ_PT10S_AVG",
            // now − 12 min = 16:23:47, floored to 10 s.
            "starttime": "2026-10-22T16:23:40Z",
            "endtime": "2026-10-22T16:35:47Z",
        ])
    }

    @Test func cloudRequest() {
        let query = items(FMIRequests.clouds(now: now))

        #expect(query == [
            "service": "WFS",
            "version": "2.0.0",
            "request": "getFeature",
            "storedquery_id": "fmi::observations::weather::simple",
            "bbox": "19,59.5,32,70.1",
            "parameters": "TotalCloudCover",
            "starttime": "2026-10-22T16:05:47Z",
            "endtime": "2026-10-22T16:35:47Z",
        ])
    }

    @Test func fractionalSecondsAreDropped() {
        let query = items(FMIRequests.clouds(now: now.addingTimeInterval(0.75)))

        #expect(query["endtime"] == "2026-10-22T16:35:47Z")
    }
}

@Suite("FMI client")
struct FMIClientTests {
    private let now = utc("2026-10-22T16:35:47Z")

    @Test func magnetometerSamplesAreGroupedByStationAndTime() async throws {
        let http = StubHTTPClient(["fmi::observations::magnetometer::simple": .fixture("magnetometer-sample.xml")])
        let client = FMIClient(http: http, stations: try ReferenceData.loadStations())

        let samples = try await client.magnetometerSamples(now: now)

        #expect(samples.count == 73)
        #expect(samples.allSatisfy { $0.stationID == "HAN" })
        #expect(samples.map(\.time) == samples.map(\.time).sorted())
        let first = try #require(samples.first)
        #expect(first.time == utc("2026-10-22T16:23:10Z"))
        #expect(first.x == 91.2)
        #expect(first.y != nil && first.z != nil)
    }

    @Test func missingValuesStayMissing() async throws {
        let http = StubHTTPClient(["fmi::observations::magnetometer::simple": .fixture("magnetometer-gaps.xml")])
        let client = FMIClient(http: http, stations: try ReferenceData.loadStations())

        let samples = try await client.magnetometerSamples(now: now)

        #expect(samples.filter { $0.x == nil }.count == 4)
    }

    @Test func unknownPositionsAreIgnored() async throws {
        let http = StubHTTPClient(["fmi::observations::magnetometer::simple": .fixture("magnetometer-sample.xml")])
        let client = FMIClient(http: http, stations: [])

        #expect(try await client.magnetometerSamples(now: now).isEmpty)
    }

    @Test func cloudObservationsKeepLatestPerPosition() async throws {
        let name = try #require(Fixtures.first(prefix: "clouds-"))
        let http = StubHTTPClient(["fmi::observations::weather::simple": .fixture(name)])
        let client = FMIClient(http: http, stations: [])

        let observations = try await client.cloudObservations(now: now)

        #expect(observations.count == 106)
        #expect(Set(observations.map(\.coordinate)).count == 106)
        #expect(observations.allSatisfy { $0.octas.map { (0...8).contains($0) } ?? true })
        // Value 9 (sky obscured) becomes unknown.
        #expect(observations.contains { $0.octas == nil })
    }

    @Test func httpErrorStatusThrows() async throws {
        let http = StubHTTPClient(["fmi::observations::weather::simple": .fixture("clouds-20261022T1635Z.xml", status: 503)])
        let client = FMIClient(http: http, stations: [])

        await #expect(throws: FMIError.httpStatus(503)) {
            try await client.cloudObservations(now: now)
        }
    }

    @Test func requestsContainNoLocationData() async throws {
        let http = StubHTTPClient([
            "fmi::observations::magnetometer::simple": .fixture("magnetometer-sample.xml"),
            "fmi::observations::weather::simple": .fixture("clouds-20261022T1635Z.xml"),
        ])
        let client = FMIClient(http: http, stations: try ReferenceData.loadStations())

        _ = try await client.magnetometerSamples(now: now)
        _ = try await client.cloudObservations(now: now)

        #expect(http.requestedURLs == [FMIRequests.magnetometer(now: now), FMIRequests.clouds(now: now)])
    }

    /// One request for every zone (research R5): identical for every user, nothing user-derived.
    @Test func cloudForecastRequest() throws {
        let zones = try AlertZones.all()
        let url = FMIRequests.cloudForecast(zones: zones)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        func value(_ name: String) -> [String] { items.filter { $0.name == name }.compactMap(\.value) }

        #expect(components.host == "opendata.fmi.fi")
        #expect(value("storedquery_id") == ["fmi::forecast::edited::weather::scandinavia::point::simple"])
        #expect(value("parameters") == ["TotalCloudCover"])
        #expect(value("timestep") == ["60"])
        #expect(value("latlon") == zones.map { "\($0.station.latitude),\($0.station.longitude)" })
        #expect(value("latlon").count == 10)
        #expect(Set(items.map(\.name)) == ["service", "version", "request", "storedquery_id", "latlon", "parameters", "timestep"])
        #expect(FMIRequests.cloudForecast(zones: zones) == url)
    }
}
