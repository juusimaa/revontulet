import Foundation

/// Whether alerts are possible at all for lack of darkness ("On, no dark nights",
/// contracts/alert-settings-states.md).
public enum AlertSeason {
    static let step: TimeInterval = 15 * 60

    /// Whether it is anything but too light at the zone at some 15-minute step within the next
    /// 24 hours from `date`, including `date` itself.
    public static func hasDarknessWithin24h(zone: AlertZone, from date: Date) -> Bool {
        let position = zone.representativePosition
        return (0..<Int(86_400 / step)).contains { index in
            SolarPosition.darkness(latitude: position.latitude, longitude: position.longitude,
                                   at: date.addingTimeInterval(Double(index) * step)) != .tooLight
        }
    }
}
