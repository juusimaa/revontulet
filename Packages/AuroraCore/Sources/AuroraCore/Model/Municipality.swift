/// A Finnish municipality from Statistics Finland's boundary data.
public struct Municipality: Sendable, Hashable, Codable, Identifiable {
    /// Statistics Finland municipality code, e.g. `091`; unique.
    public var code: String
    public var nameFi: String
    /// Swedish name; nil when the municipality has no separate Swedish name.
    public var nameSv: String?
    /// A point inside the municipality, used for manual selection.
    public var representativePoint: Coordinate
    public var boundingBox: BoundingBox
    public var polygons: [Polygon]

    public var id: String { code }

    public init(
        code: String, nameFi: String, nameSv: String?, representativePoint: Coordinate,
        boundingBox: BoundingBox, polygons: [Polygon]
    ) {
        self.code = code
        self.nameFi = nameFi
        self.nameSv = nameSv
        self.representativePoint = representativePoint
        self.boundingBox = boundingBox
        self.polygons = polygons
    }

    /// The Swedish name when Swedish is preferred and one exists, otherwise the Finnish name.
    public func displayName(preferSwedish: Bool) -> String {
        preferSwedish ? (nameSv ?? nameFi) : nameFi
    }
}
