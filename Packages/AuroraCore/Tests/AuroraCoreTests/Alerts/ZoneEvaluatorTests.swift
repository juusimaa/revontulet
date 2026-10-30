import Foundation
import Testing
@testable import AuroraCore

@Suite("Zone evaluator")
struct ZoneEvaluatorTests {
    private let strong = try! RecordedNight.named("20261014")
    private let stations = try! ReferenceData.loadStations()
    /// 2026-10-14 22:00 UTC: strong activity in the north.
    private let midnight = utc("2026-10-14T22:00:00Z")

    @Test func oneConditionPerZoneWithData() async throws {
        let evaluator = try ZoneEvaluator(http: NightReplayHTTPClient(strong))

        let conditions = try await evaluator.evaluate(at: midnight)

        #expect(conditions.map(\.zoneID).sorted() == stations.map(\.id).sorted())
        for condition in conditions {
            #expect(condition.activityStationID == condition.zoneID)
            #expect(abs(condition.dataTime.timeIntervalSince(midnight)) <= 20)
        }
    }

    @Test func stationOutageUsesNextNearestStation() async throws {
        let http = try NightReplayHTTPClient(strong)
        http.dropStations(["OUJ"])
        let evaluator = try ZoneEvaluator(http: http)

        let conditions = try await evaluator.evaluate(at: midnight)

        let oujPosition = try #require(stations.first { $0.id == "OUJ" }).coordinate
        let nextNearest = stations.filter { $0.id != "OUJ" }
            .min { Geo.distanceKm(oujPosition, $0.coordinate) < Geo.distanceKm(oujPosition, $1.coordinate) }!
        let ouj = try #require(conditions.first { $0.zoneID == "OUJ" })
        #expect(ouj.activityStationID == nextNearest.id)
        #expect(conditions.count == 10)
    }

    @Test func noValidRAnywhereGivesNoConditions() async throws {
        let http = try NightReplayHTTPClient(strong)
        http.dropStations(Set(stations.map(\.id)))
        let evaluator = try ZoneEvaluator(http: http)

        #expect(try await evaluator.evaluate(at: midnight).isEmpty)
    }

    @Test func failedCloudFetchGivesUnknownClouds() async throws {
        let http = try NightReplayHTTPClient(strong)
        http.setFailing(NightReplayHTTPClient.cloudsQuery, true)
        let evaluator = try ZoneEvaluator(http: http)

        let conditions = try await evaluator.evaluate(at: midnight)

        #expect(conditions.count == 10)
        #expect(conditions.allSatisfy { !$0.chance.cloudsIncluded })
    }

    @Test func failedMagnetometerFetchThrowsOffline() async throws {
        let http = try NightReplayHTTPClient(strong)
        http.setFailing(NightReplayHTTPClient.magnetometerQuery, true)
        let evaluator = try ZoneEvaluator(http: http)

        await #expect(throws: AuroraServiceError.offline) { try await evaluator.evaluate(at: midnight) }
    }

    @Test func fetchesNoMoreOftenThanAuroraService() async throws {
        let http = try NightReplayHTTPClient(strong)
        let evaluator = try ZoneEvaluator(http: http)

        for minutes in [0.0, 1, 4, 5, 9, 10, 14, 15, 20] {
            _ = try await evaluator.evaluate(at: midnight.addingTimeInterval(minutes * 60))
        }

        // Magnetometer at 0, 5, 10, 15, 20; clouds at 0, 10, 20.
        #expect(http.requests(for: NightReplayHTTPClient.magnetometerQuery).count == 5)
        #expect(http.requests(for: NightReplayHTTPClient.cloudsQuery).count == 3)
    }

    @Test func requestsContainNothingAboutZonesOrUsers() async throws {
        let http = try NightReplayHTTPClient(strong)
        _ = try await ZoneEvaluator(http: http).evaluate(at: midnight)

        #expect(http.requestedURLs == [FMIRequests.magnetometer(now: midnight), FMIRequests.clouds(now: midnight)]
            || http.requestedURLs == [FMIRequests.clouds(now: midnight), FMIRequests.magnetometer(now: midnight)])
    }

    /// The strong night of 2026-10-14 (a thin crescent) replayed 41 days later under the full moon
    /// of 2026-11-24: every zone that was High under a dark, clear sky, and has the moon up at its
    /// representative position, becomes Moderate because of the bright moon.
    @Test func brightMoonAtTheZonePositionLowersHighToModerate() async throws {
        let shift: TimeInterval = 41 * 86_400
        let moonlit = midnight.addingTimeInterval(shift)
        let darkSky = try await ZoneEvaluator(http: NightReplayHTTPClient(strong)).evaluate(at: midnight)
        let underMoon = try await ZoneEvaluator(http: NightReplayHTTPClient(strong, shift: shift)).evaluate(at: moonlit)

        var checked = 0
        for station in stations {
            guard let before = darkSky.first(where: { $0.zoneID == station.id }),
                  before.chance.level == .high, before.chance.cloudsIncluded,
                  SolarPosition.darkness(latitude: station.latitude, longitude: station.longitude, at: moonlit) == .dark
            else { continue }
            let moon = MoonPosition.state(latitude: station.latitude, longitude: station.longitude, at: moonlit)
            let after = try #require(underMoon.first { $0.zoneID == station.id })
            #expect(!MoonPosition.state(latitude: station.latitude, longitude: station.longitude, at: midnight).isBright)
            if moon.isBright {
                #expect(after.chance == Chance(level: .moderate, limitingFactor: .moon, cloudsIncluded: true), "\(station.id)")
                #expect(after.reason == .brightMoon, "\(station.id)")
                checked += 1
            } else {
                #expect(after.chance == before.chance, "\(station.id)")
            }
        }
        #expect(checked > 0)
    }

    /// An alert and the app's own result agree for the same data and position.
    @Test(arguments: ["2026-10-14T18:45:00Z", "2026-10-14T22:00:00Z", "2026-10-15T03:30:00Z"])
    func agreesWithAuroraService(time: String) async throws {
        let now = utc(time)
        let conditions = try await ZoneEvaluator(http: NightReplayHTTPClient(strong)).evaluate(at: now)

        for station in stations {
            let service = try AuroraService(http: NightReplayHTTPClient(strong), cache: InMemoryResultCache())
            let place = Place(coordinate: station.coordinate, municipalityCode: "000", source: .manual)
            let result = try await service.refresh(for: place, at: now, force: true)
            let condition = try #require(conditions.first { $0.zoneID == station.id })

            #expect(condition.chance == result.chance, "\(station.id)")
            #expect(condition.reason == result.reason, "\(station.id)")
            #expect(condition.activityStationID == result.reading.station.id, "\(station.id)")
            #expect(condition.dataTime == result.reading.measuredAt, "\(station.id)")
        }
    }

    /// Replaying a recorded night in 5-minute cycles gives exactly the alerts in its
    /// expected.json, written by the independent tools/alert-reference.py (SC-002).
    @Test(arguments: RecordedNight.names)
    func recordedNightGivesExpectedAlerts(name: String) async throws {
        let night = try RecordedNight.named(name)
        let evaluator = try ZoneEvaluator(http: NightReplayHTTPClient(night))
        var states: [String: ZoneAlertState] = [:]
        var alerts: [RecordedNight.ExpectedAlert] = []

        for now in night.cycles {
            for condition in try await evaluator.evaluate(at: now) {
                let state = states[condition.zoneID] ?? ZoneAlertState(zoneID: condition.zoneID)
                let (decision, next) = AlertPolicy.decide(condition: condition, state: state, now: now)
                states[condition.zoneID] = next
                if let decision {
                    alerts.append(.init(zone: decision.zoneID, level: decision.level == .high ? "high" : "moderate", time: now))
                }
            }
        }

        #expect(Set(alerts) == Set(night.expected))
        #expect(alerts.count == night.expected.count)
    }
}
