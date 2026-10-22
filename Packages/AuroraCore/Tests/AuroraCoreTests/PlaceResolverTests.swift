import Testing
@testable import AuroraCore

@Suite("Place resolution")
struct PlaceResolverTests {
    private static let resolver = try! PlaceResolver()

    @Test(arguments: [
        ("Helsinki centre", 60.1699, 24.9384, "Helsinki"),
        ("Suomenlinna", 60.146, 24.988, "Helsinki"),
        ("Tornio centre", 65.846, 24.146, "Tornio"),
        ("Hailuoto", 65.03, 24.72, "Hailuoto"),
        ("Mariehamn", 60.0973, 19.9348, "Maarianhamina"),
        ("Utsjoki", 69.9078, 27.0265, "Utsjoki"),
        ("Rovaniemi", 66.50, 25.73, "Rovaniemi"),
    ])
    func resolvesInsideFinland(name: String, latitude: Double, longitude: Double, expected: String) throws {
        guard case .inside(let municipality) = Self.resolver.resolve(latitude: latitude, longitude: longitude) else {
            Issue.record("\(name) resolved outside coverage")
            return
        }
        #expect(municipality.nameFi == expected, "\(name)")
    }

    @Test(arguments: [
        ("Stockholm", 59.33, 18.07),
        ("Open Baltic", 59.0, 21.5),
        ("Tallinn", 59.437, 24.745),
        ("Gulf of Finland, 16 km off Espoo", 59.95, 24.9),
    ])
    func outsideCoverage(name: String, latitude: Double, longitude: Double) {
        #expect(Self.resolver.resolve(latitude: latitude, longitude: longitude) == .outsideCoverage, "\(name)")
    }

    @Test func nearestBoundaryWithinFifteenKilometres() throws {
        // At sea about 6.5 km south of Helsinki's boundary.
        guard case .inside(let municipality) = Self.resolver.resolve(latitude: 60.05, longitude: 24.95) else {
            Issue.record("expected Helsinki")
            return
        }
        #expect(municipality.nameFi == "Helsinki")
    }

    @Test func municipalityByCode() {
        #expect(Self.resolver.municipality(code: "091")?.nameFi == "Helsinki")
        #expect(Self.resolver.municipality(code: "999") == nil)
    }
}
