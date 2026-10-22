import Testing
@testable import AuroraCore

@Suite("Municipality search")
struct MunicipalitySearchTests {
    private static let resolver = try! PlaceResolver()

    private func names(_ query: String, limit: Int = 10) -> [String] {
        Self.resolver.search(query, limit: limit).map(\.nameFi)
    }

    @Test(arguments: [
        ("hels", "Helsinki"),
        ("HELS", "Helsinki"),
        ("helsingf", "Helsinki"),
        ("jyvaskyla", "Jyväskylä"),
        ("Jyväskylä", "Jyväskylä"),
        ("Mariehamn", "Maarianhamina"),
        ("Maarianhamina", "Maarianhamina"),
        ("utsj", "Utsjoki"),
        ("  rovaniemi ", "Rovaniemi"),
    ])
    func findsByFinnishOrSwedishName(query: String, expected: String) {
        #expect(names(query).first == expected, "\(query)")
    }

    @Test func prefixMatchesComeBeforeSubstringMatches() {
        // "joki" starts Jokioinen and is inside Utsjoki, Seinäjoki and many others.
        let result = names("joki", limit: 50)
        let firstSubstring = result.firstIndex { !$0.lowercased().hasPrefix("joki") }
        let lastPrefix = result.lastIndex { $0.lowercased().hasPrefix("joki") }
        #expect(result.contains("Jokioinen"))
        #expect(result.contains("Utsjoki"))
        if let firstSubstring, let lastPrefix {
            #expect(lastPrefix < firstSubstring)
        }
    }

    @Test func swedishPrefixRanksAsPrefix() {
        // "Esbo" is a prefix of Espoo's Swedish name.
        #expect(names("esbo").first == "Espoo")
    }

    @Test func limitIsRespected() {
        #expect(Self.resolver.search("a", limit: 5).count == 5)
        #expect(Self.resolver.search("", limit: 3).count == 3)
    }

    @Test func emptyQueryListsAlphabetically() {
        let all = Self.resolver.search("", limit: 1000)
        #expect(all.count == 308)
        #expect(all.first?.nameFi == "Akaa")
        // Finnish collation: Å, Ä and Ö sort after Z.
        #expect(all.last?.nameFi == "Äänekoski")
        let whitespace = Self.resolver.search("   ", limit: 1000)
        #expect(whitespace.map(\.code) == all.map(\.code))
    }

    @Test func noMatchReturnsEmpty() {
        #expect(Self.resolver.search("Stockholm", limit: 10).isEmpty)
    }
}
