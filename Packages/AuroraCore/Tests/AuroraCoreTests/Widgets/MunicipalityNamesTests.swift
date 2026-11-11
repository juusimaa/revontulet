import Foundation
import Testing
@testable import AuroraCore

@Suite("Municipality names")
struct MunicipalityNamesTests {
    @Test func knownCodeMatchesPlaceResolver() throws {
        let resolver = try PlaceResolver()
        let full = try #require(resolver.municipality(code: "091"))
        let light = try #require(try MunicipalityNames.lookup(code: "091"))
        #expect(light.code == full.code)
        #expect(light.nameFi == full.nameFi)
        #expect(light.nameSv == full.nameSv)
        #expect(light.nameSv != nil)
        #expect(light.representativePoint == full.representativePoint)
    }

    @Test func unknownCodeGivesNil() throws {
        #expect(try MunicipalityNames.lookup(code: "999") == nil)
    }

    @Test func displayNamePrefersSwedishWhenPresent() {
        let point = Coordinate(latitude: 60, longitude: 24)
        let both = MunicipalityName(code: "091", nameFi: "Helsinki", nameSv: "Helsingfors", representativePoint: point)
        let fiOnly = MunicipalityName(code: "005", nameFi: "Alajärvi", nameSv: nil, representativePoint: point)
        #expect(both.displayName(preferSwedish: true) == "Helsingfors")
        #expect(both.displayName(preferSwedish: false) == "Helsinki")
        #expect(fiOnly.displayName(preferSwedish: true) == "Alajärvi")
    }

    @Test func decodeTypeHasNoPolygonField() throws {
        let data = try #require(
            Bundle.module.url(forResource: "municipalities", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
                ?? Self.packageResource())
        let file = try JSONDecoder().decode(MunicipalityNames.File.self, from: data)
        #expect(!file.municipalities.isEmpty)
        let labels = Set(Mirror(reflecting: file.municipalities[0]).children.compactMap(\.label))
        #expect(labels == ["code", "nameFi", "nameSv", "point"])
        #expect(!labels.contains("polygons"))
        #expect(!labels.contains("bbox"))
    }

    private static func packageResource() -> Data? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AuroraCore/Resources/municipalities.json")
        return try? Data(contentsOf: url)
    }
}
