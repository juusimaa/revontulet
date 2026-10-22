/// FMI's activity levels from a station's R value and its own thresholds (research.md R3).
public enum ActivityClassifier {
    public static func level(r: Double, station: Station) -> ActivityLevel {
        if r >= station.redThreshold { return .probable }
        if r >= station.yellowThreshold { return .possible }
        return .unlikely
    }
}
