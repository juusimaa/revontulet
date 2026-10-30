/// Latitude band of a zone, for the "soon" thresholds and the Kp mapping
/// (specs/003-aurora-outlook/contracts/soon-rules.md#bands).
public enum Band: String, Sendable, Hashable, Codable, CaseIterable {
    case north
    case central
    case south

    /// The band of a zone (station code), or nil for an unknown code.
    public static func of(zoneID: String) -> Band? {
        switch zoneID {
        case "KEV", "KIL", "IVA", "MUO", "PEL": .north
        case "RAN", "OUJ", "MEK", "HAN": .central
        case "TAR": .south
        default: nil
        }
    }
}
