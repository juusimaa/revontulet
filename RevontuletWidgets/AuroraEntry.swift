import AuroraCore
import WidgetKit

/// What one widget draws at one moment. `snapshot` is nil until there is a result to show; the
/// states for no place, no data and the gallery sample are added with them (US3).
struct AuroraEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// The place name in the system language, already resolved by the provider.
    let placeName: String
}
