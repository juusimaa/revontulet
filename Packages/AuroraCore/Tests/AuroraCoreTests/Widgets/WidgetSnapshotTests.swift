import Foundation
import Testing
@testable import AuroraCore

@Suite("WidgetSnapshot")
struct WidgetSnapshotTests {
    private static let station = Station(
        id: "KEV", name: "Kevo", latitude: 69.761, longitude: 27.01, yellowThreshold: 55, redThreshold: 165)
    private static let measuredAt = utc("2026-10-22T16:35:00Z")

    private static func place(_ code: String) -> Place {
        Place(coordinate: Coordinate(latitude: 69.9078, longitude: 27.0265), municipalityCode: code, source: .manual)
    }

    private static func result(
        level: ChanceLevel = .high, factor: LimitingFactor? = nil, activity: ActivityLevel? = .probable,
        r: Double? = 182.37, darkness: Darkness = .dark, clouds: CloudCondition = .clear, code: String = "890"
    ) -> AuroraResult {
        AuroraResult(
            place: place(code),
            chance: Chance(level: level, limitingFactor: factor, cloudsIncluded: clouds != .unknown),
            reading: StationReading(station: station, r: r, measuredAt: measuredAt, activity: activity),
            distanceToStationKm: 16.4, usedMoreDistantStation: false, darkness: darkness,
            clouds: CloudCover(condition: clouds),
            moon: MoonState(altitude: -10, illuminatedFraction: 0.2, phase: .waxingCrescent, isBright: false),
            computedAt: measuredAt)
    }

    private static func night(_ which: NightKind) -> NightOutlook {
        NightOutlook(which: which, night: .tooLight, availability: .tooLight)
    }

    private static func outlook(code: String) -> OutlookSnapshot {
        let now = measuredAt
        return OutlookSnapshot(
            place: place(code), zoneID: "z", computedAt: now,
            soon: SoonSignal(state: .likely, arrivalMinutes: 30, showsOnMainScreen: true),
            outlook: Outlook(tonight: night(.tonight), tomorrow: night(.tomorrow), computedAt: now))
    }

    @Test(arguments: ChanceLevel.allCases)
    func levelIsCopied(_ level: ChanceLevel) {
        let r = Self.result(level: level)
        let snapshot = WidgetSnapshot.make(result: r, outlook: nil, now: Self.measuredAt)
        #expect(snapshot.level == level)
    }

    @Test(arguments: [
        Self.result(level: .none, factor: .light, darkness: .tooLight),
        Self.result(level: .none, factor: .clouds, clouds: .overcast),
        Self.result(level: .low, factor: .clouds, clouds: .partly),
        Self.result(level: .low, factor: .activity, activity: .unlikely),
        Self.result(level: .moderate, factor: .activity, activity: .possible),
        Self.result(level: .high),
    ])
    func reasonAndFieldsAreCopied(_ r: AuroraResult) {
        let s = WidgetSnapshot.make(result: r, outlook: nil, now: Self.measuredAt)
        #expect(s.reason == r.reason)
        #expect(s.level == r.chance.level)
        #expect(s.cloudsIncluded == r.chance.cloudsIncluded)
        #expect(s.municipalityCode == "890")
        #expect(s.stationName == "Kevo")
        #expect(s.activity == r.reading.activity)
        #expect(s.rValue == r.reading.r)
        #expect(s.measuredAt == Self.measuredAt)
    }

    @Test func staleOnlyAfterThirtyMinutes() {
        let r = Self.result()
        let edge = Self.measuredAt.addingTimeInterval(30 * 60)
        #expect(!WidgetSnapshot.make(result: r, outlook: nil, now: edge).isStale)
        #expect(WidgetSnapshot.make(result: r, outlook: nil, now: edge.addingTimeInterval(1)).isStale)
    }

    @Test func outlookOfSameMunicipalityIsUsed() {
        let o = Self.outlook(code: "890")
        let s = WidgetSnapshot.make(result: Self.result(), outlook: o, now: Self.measuredAt)
        #expect(s.soon == o.soon)
        #expect(s.tonight?.which == .tonight)
        #expect(s.tonight == o.outlook?.tonight)
    }

    @Test func outlookOfAnotherMunicipalityIsIgnored() {
        let s = WidgetSnapshot.make(result: Self.result(), outlook: Self.outlook(code: "091"), now: Self.measuredAt)
        #expect(s.soon == nil)
        #expect(s.tonight == nil)
    }

    @Test func missingOutlook() {
        let s = WidgetSnapshot.make(result: Self.result(), outlook: nil, now: Self.measuredAt)
        #expect(s.soon == nil)
        #expect(s.tonight == nil)
    }

    @Test func outlookWithoutNightsKeepsSoon() {
        var o = Self.outlook(code: "890")
        o.outlook = nil
        let s = WidgetSnapshot.make(result: Self.result(), outlook: o, now: Self.measuredAt)
        #expect(s.soon == o.soon)
        #expect(s.tonight == nil)
    }

    @Test func missingRValue() {
        let r = Self.result(level: .none, factor: .light, activity: nil, r: nil, darkness: .tooLight)
        let s = WidgetSnapshot.make(result: r, outlook: nil, now: Self.measuredAt)
        #expect(s.rValue == nil)
        #expect(s.reason == r.reason)
    }
}
