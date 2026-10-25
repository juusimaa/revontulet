/// Localisation keys and arguments of an alert (contracts/push-notification.md). The service
/// sends the keys; iOS looks up the text in the device language, so the language never leaves
/// the device (FR-010).
public struct AlertMessage: Sendable, Hashable {
    public var titleKey: String
    public var bodyKey: String
    /// The zone's station name, or nothing for the test message.
    public var arguments: [String]

    public init(titleKey: String, bodyKey: String, arguments: [String]) {
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.arguments = arguments
    }

    public static func make(for decision: AlertDecision) -> AlertMessage {
        let condition = decision.condition
        let base: String
        switch (decision.level, condition.reason) {
        case (.moderate, .twilight): base = "alert.body.twilight"
        case (.moderate, .partlyCloudy): base = "alert.body.partlyCloudy"
        case (.moderate, _): base = "alert.body.someActivity"
        default: base = "alert.body.goodConditions"
        }
        // Partly cloudy means the clouds are known.
        let bodyKey = condition.chance.cloudsIncluded || base == "alert.body.partlyCloudy" ? base : base + ".cloudsUnknown"
        return AlertMessage(
            titleKey: decision.level == .high ? "alert.title.high" : "alert.title.moderate",
            bodyKey: bodyKey,
            arguments: [stationNames[decision.zoneID] ?? decision.zoneID])
    }

    public static let test = AlertMessage(titleKey: "alert.title.test", bodyKey: "alert.body.test", arguments: [])

    public static let titleKeys = ["alert.title.high", "alert.title.moderate", "alert.title.test"]

    public static let bodyKeys = [
        "alert.body.goodConditions",
        "alert.body.goodConditions.cloudsUnknown",
        "alert.body.someActivity",
        "alert.body.someActivity.cloudsUnknown",
        "alert.body.twilight",
        "alert.body.twilight.cloudsUnknown",
        "alert.body.partlyCloudy",
        "alert.body.test",
    ]

    /// Every key `make` and `test` can return; the app checks all exist in fi, sv and en.
    public static let allKeys = titleKeys + bodyKeys

    /// Station names by zone, as FMI publishes them (not translated).
    private static let stationNames: [String: String] = Dictionary(
        uniqueKeysWithValues: ((try? ReferenceData.loadStations()) ?? []).map { ($0.id, $0.name) })
}
