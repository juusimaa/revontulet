import Testing
@testable import AuroraCore

@Suite("Bands (contracts/soon-rules.md#bands)")
struct BandTests {
    @Test(arguments: [
        ("KEV", Band.north), ("KIL", .north), ("IVA", .north), ("MUO", .north), ("PEL", .north),
        ("RAN", .central), ("OUJ", .central), ("MEK", .central), ("HAN", .central),
        ("TAR", .south),
    ])
    func stationBand(zoneID: String, band: Band) {
        #expect(Band.of(zoneID: zoneID) == band)
    }

    @Test func unknownCodeHasNoBand() {
        #expect(Band.of(zoneID: "XXX") == nil)
        #expect(Band.of(zoneID: "") == nil)
    }

    @Test func everyStationHasABand() throws {
        for station in try ReferenceData.loadStations() {
            #expect(Band.of(zoneID: station.id) != nil, "\(station.id)")
        }
    }
}
