import Foundation

/// Where a position is, in terms of the area the app covers.
public enum PlaceResolution: Sendable, Equatable {
    case inside(Municipality)
    case outsideCoverage
}

/// Resolves positions to Finnish municipalities using bundled boundaries; never uses the network.
public struct PlaceResolver: Sendable {
    /// A position outside every municipality still counts as the nearest one within this distance
    /// (islands, boats, generalised coastline).
    static let nearbyDistanceKm = 15.0

    public let municipalities: [Municipality]
    private let byCode: [String: Municipality]
    /// Municipalities in Finnish alphabetical order with their names folded for search.
    private let searchIndex: [SearchEntry]

    public init() throws {
        self.init(municipalities: try ReferenceData.loadMunicipalities())
    }

    init(municipalities: [Municipality]) {
        self.municipalities = municipalities
        byCode = Dictionary(uniqueKeysWithValues: municipalities.map { ($0.code, $0) })
        let finnish = Locale(identifier: "fi_FI")
        searchIndex = municipalities
            .sorted { $0.nameFi.compare($1.nameFi, locale: finnish) == .orderedAscending }
            .map { SearchEntry(municipality: $0, names: [$0.nameFi, $0.nameSv].compactMap { $0.map(Self.fold) }) }
    }

    /// The municipality containing the position, else the nearest one within 15 km, else outside
    /// coverage (FR-001e, FR-003).
    public func resolve(latitude: Double, longitude: Double) -> PlaceResolution {
        let point = Coordinate(latitude: latitude, longitude: longitude)
        if let match = municipalities.first(where: { $0.boundingBox.contains(point) && Geo.contains($0.polygons, point) }) {
            return .inside(match)
        }

        // Skip municipalities whose bounding box is clearly further away than the limit.
        let margin = Self.nearbyDistanceKm / Geo.kmPerDegree
        let lonMargin = margin / max(0.1, cos(latitude * .pi / 180))
        let nearest = municipalities
            .filter {
                $0.boundingBox.minLatitude - margin <= latitude && latitude <= $0.boundingBox.maxLatitude + margin
                    && $0.boundingBox.minLongitude - lonMargin <= longitude
                    && longitude <= $0.boundingBox.maxLongitude + lonMargin
            }
            .map { (municipality: $0, distance: Geo.distanceToBoundaryKm(point, $0.polygons)) }
            .min { $0.distance < $1.distance }
        if let nearest, nearest.distance <= Self.nearbyDistanceKm {
            return .inside(nearest.municipality)
        }
        return .outsideCoverage
    }

    public func municipality(code: String) -> Municipality? {
        byCode[code]
    }

    /// Municipalities whose Finnish or Swedish name contains `text`, ignoring case and diacritics
    /// (FR-010). Names starting with the text come first; each group is in Finnish alphabetical
    /// order. An empty query lists all municipalities alphabetically.
    public func search(_ text: String, limit: Int) -> [Municipality] {
        let query = Self.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return searchIndex.prefix(limit).map(\.municipality) }
        var prefixMatches: [Municipality] = []
        var substringMatches: [Municipality] = []
        for entry in searchIndex {
            if entry.names.contains(where: { $0.hasPrefix(query) }) {
                prefixMatches.append(entry.municipality)
            } else if entry.names.contains(where: { $0.contains(query) }) {
                substringMatches.append(entry.municipality)
            }
        }
        return Array((prefixMatches + substringMatches).prefix(limit))
    }

    private static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private struct SearchEntry: Sendable {
        let municipality: Municipality
        let names: [String]
    }
}

extension Place {
    /// A manually chosen municipality, located at its representative point.
    public init(manual municipality: Municipality) {
        self.init(
            coordinate: municipality.representativePoint, municipalityCode: municipality.code, source: .manual)
    }
}
