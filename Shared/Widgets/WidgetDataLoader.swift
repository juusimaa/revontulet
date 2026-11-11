import AuroraCore
import Foundation

/// The one place the widget extension fetches (research R1, R7): owns the services on the shared App Group
/// caches, fetches only what `WidgetRefreshPolicy` says is due, and lets concurrent timeline requests for
/// several widget families share one fetch. Never forces a fetch.
actor WidgetDataLoader {
    static let shared = WidgetDataLoader(
        http: URLSessionHTTPClient(), resultCache: FileResultCache(), outlookCache: FileOutlookCache())

    private let service: AuroraService
    private let outlookService: OutlookService
    private let resultCache: any ResultCache
    private let outlookCache: any OutlookCache
    // The municipality keeps a fetch for another place from being shared.
    private var resultTask: (code: String, task: Task<AuroraResult?, Never>)?
    private var outlookTask: (code: String, task: Task<OutlookSnapshot?, Never>)?

    init(http: any HTTPClient, resultCache: any ResultCache, outlookCache: any OutlookCache) {
        self.service = try! AuroraService(http: http, cache: resultCache)
        self.outlookService = OutlookService(http: http, cache: outlookCache)
        self.resultCache = resultCache
        self.outlookCache = outlookCache
    }

    /// The newest stored result for `place`: fetched first when `WidgetRefreshPolicy.resultNeedsFetch` says
    /// so (one fetch shared by concurrent callers), otherwise the cached one. Offline, no data or a cancelled
    /// fetch leave the store unchanged and return what was cached (nil when nothing was).
    func result(for place: Place, at now: Date) async -> AuroraResult? {
        let code = place.municipalityCode
        if let resultTask, resultTask.code == code { return await resultTask.task.value }
        // Set before any await: the actor is reentrant.
        let task = Task { [service, resultCache] () -> AuroraResult? in
            let cached = await resultCache.load()
            guard WidgetRefreshPolicy.resultNeedsFetch(cached: cached, place: place, now: now) else { return cached }
            return (try? await service.refresh(for: place, at: now, force: false)) ?? cached
        }
        resultTask = (code, task)
        let value = await task.value
        if resultTask?.task == task { resultTask = nil }
        return value
    }

    /// Same for the outlook snapshot (medium widget only); the zone comes from `AlertZones`.
    func outlook(for place: Place, at now: Date) async -> OutlookSnapshot? {
        let code = place.municipalityCode
        if let outlookTask, outlookTask.code == code { return await outlookTask.task.value }
        let task = Task { [outlookService, outlookCache] () -> OutlookSnapshot? in
            let cached = await outlookCache.load()
            guard WidgetRefreshPolicy.outlookNeedsFetch(cached: cached, place: place, now: now),
                let zones = try? AlertZones.all(), !zones.isEmpty
            else { return cached }
            let zoneID = AlertZones.zone(for: place.coordinate, previous: cached?.zoneID, in: zones).id
            return await outlookService.refresh(for: place, zoneID: zoneID, at: now, force: false)
        }
        outlookTask = (code, task)
        let value = await task.value
        if outlookTask?.task == task { outlookTask = nil }
        return value
    }

    /// Cancels any fetch in flight so it writes nothing (the provider's time budget ran out).
    func cancel() {
        resultTask?.task.cancel()
        outlookTask?.task.cancel()
        resultTask = nil
        outlookTask = nil
    }
}
