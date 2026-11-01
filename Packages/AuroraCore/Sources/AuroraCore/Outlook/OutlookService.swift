import Foundation

/// Stores the last outlook snapshot between launches, separately from the headline's
/// `ResultCache`, so a corrupt or old snapshot never affects the headline.
public protocol OutlookCache: Sendable {
    func load() async -> OutlookSnapshot?
    func save(_ snapshot: OutlookSnapshot) async
}

/// A cache that lives only as long as the process, for tests and previews.
public actor InMemoryOutlookCache: OutlookCache {
    private var snapshot: OutlookSnapshot?

    public init(_ snapshot: OutlookSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() -> OutlookSnapshot? {
        snapshot
    }

    public func save(_ snapshot: OutlookSnapshot) {
        self.snapshot = snapshot
    }
}

/// Fetches the NOAA and FMI forecast inputs and turns them into the "soon" signal and the
/// outlook for a place (specs/003-aurora-outlook/contracts/aurora-core-outlook-api.md).
///
/// Separate from `AuroraService`, so a NOAA failure never reaches the headline (FR-020). Each
/// input has its own due time (research R8) and fails on its own: a failed fetch keeps the last
/// good input and is retried on the next refresh, never in a loop.
public actor OutlookService {
    static let solarWindInterval: TimeInterval = 5 * 60
    static let kpInterval: TimeInterval = 60 * 60
    static let alertsInterval: TimeInterval = 60 * 60
    static let cloudsInterval: TimeInterval = 3 * 60 * 60

    private let http: any HTTPClient
    private let cache: any OutlookCache
    private let zones: [AlertZone]
    /// The last snapshot, for hysteresis; loaded from the cache on first use.
    private var previous: OutlookSnapshot?
    private var loadedCache = false
    private var solarWind = DueInput<[SolarWindSample]>(interval: OutlookService.solarWindInterval)
    private var kp = DueInput<KpForecast>(interval: OutlookService.kpInterval)
    private var watches = DueInput<[StormWatch]>(interval: OutlookService.alertsInterval)
    private var clouds = DueInput<[CloudForecast]>(interval: OutlookService.cloudsInterval)

    public init(http: any HTTPClient, cache: any OutlookCache) {
        self.http = http
        self.cache = cache
        // The bundled station table is part of the package; without it there is no cloud forecast.
        zones = (try? AlertZones.all()) ?? []
    }

    /// The last stored snapshot, if any. Never touches the network.
    public func cachedSnapshot() async -> OutlookSnapshot? {
        await loadCacheOnce()
        return previous
    }

    /// Fetches what is due (or everything with `force`), computes the snapshot for `place` at
    /// `date`, stores it and returns it. Never throws: missing inputs give an unknown "soon"
    /// state or an unavailable night.
    public func refresh(for place: Place, zoneID: String, at date: Date, force: Bool) async -> OutlookSnapshot {
        await loadCacheOnce()

        // Every due input is fetched at the same time; each one fails on its own.
        let zones = zones
        async let solarWindFetch = solarWind.isDue(at: date, force: force)
            ? fetch(NOAARequests.propagatedSolarWind, NOAAParser.propagatedSolarWind) : nil
        async let kpFetch = kp.isDue(at: date, force: force)
            ? fetch(NOAARequests.kpForecast) { try NOAAParser.kpForecast($0, fetchedAt: date) } : nil
        async let watchesFetch = watches.isDue(at: date, force: force)
            ? fetch(NOAARequests.alerts) { try NOAAParser.stormWatches($0, now: date) } : nil
        async let cloudsFetch = clouds.isDue(at: date, force: force) && !zones.isEmpty
            ? fetch(FMIRequests.cloudForecast(zones: zones)) { try BsWfsParser.cloudForecasts($0, zones: zones, fetchedAt: date) }
            : nil
        solarWind.update(await solarWindFetch, at: date)
        kp.update(await kpFetch, at: date)
        watches.update(await watchesFetch, at: date)
        clouds.update(await cloudsFetch, at: date)

        // Recomputed on every refresh from the newest inputs, so "tonight" moves on at the end
        // of a dark period even when nothing new was fetched.
        let outlook = Band.of(zoneID: zoneID).map { band in
            OutlookCalculator.outlook(
                place: place.coordinate, band: band, now: date, kp: kp.value, watches: watches.value ?? [],
                clouds: clouds.value?.first { $0.zoneID == zoneID })
        }
        let snapshot = OutlookSnapshot(
            place: place, zoneID: zoneID, computedAt: date,
            soon: soon(for: place, zoneID: zoneID, at: date), outlook: outlook,
            samples: solarWind.fetched, forecast: kp.value, watches: watches.fetched, clouds: clouds.fetched)
        previous = snapshot
        await cache.save(snapshot)
        return snapshot
    }

    private func soon(for place: Place, zoneID: String, at date: Date) -> SoonSignal {
        guard let band = Band.of(zoneID: zoneID) else { return .unknown }
        // Hysteresis only against the same place's last state.
        let previousState = previous.flatMap { $0.place.isSame(as: place) ? $0.soon.state : nil }
        var signal = SoonCalculator.signal(samples: solarWind.value ?? [], band: band, now: date, previous: previousState)
        signal.showsOnMainScreen = SoonCalculator.showsOnMainScreen(signal, at: place.coordinate, now: date)
        return signal
    }

    private func loadCacheOnce() async {
        guard !loadedCache else { return }
        loadedCache = true
        guard let cached = await cache.load() else { return }
        previous = cached
        if let samples = cached.samples { solarWind = DueInput(interval: Self.solarWindInterval, samples) }
        if let forecast = cached.forecast {
            kp = DueInput(interval: Self.kpInterval, value: forecast, fetchedAt: forecast.fetchedAt)
        }
        if let cachedWatches = cached.watches { watches = DueInput(interval: Self.alertsInterval, cachedWatches) }
        if let cachedClouds = cached.clouds { clouds = DueInput(interval: Self.cloudsInterval, cachedClouds) }
    }

    /// nil when the request or the parsing fails; the caller keeps its last good input.
    private func fetch<Value>(_ url: URL, _ parse: @Sendable (Data) throws -> Value) async -> Value? {
        guard let (data, status) = try? await http.get(url), status == 200 else { return nil }
        return try? parse(data)
    }
}

extension Place {
    /// The same municipality and source: a new location fix within it is still the same place.
    func isSame(as other: Place) -> Bool {
        municipalityCode == other.municipalityCode && source == other.source
    }
}

/// An input with the time it was last fetched successfully.
struct DueInput<Value: Sendable> {
    var value: Value?
    var fetchedAt: Date?
    let interval: TimeInterval

    init(interval: TimeInterval, value: Value? = nil, fetchedAt: Date? = nil) {
        self.interval = interval
        self.value = value
        self.fetchedAt = fetchedAt
    }

    /// Due when never fetched, when `interval` has passed since the last success, or with `force`.
    /// A failed fetch does not move `fetchedAt`, so the next refresh tries again.
    func isDue(at date: Date, force: Bool) -> Bool {
        force || fetchedAt.map { date.timeIntervalSince($0) >= interval } ?? true
    }

    /// Takes a fetched value; a failed fetch (nil) keeps the last good one.
    mutating func update(_ fetched: Value?, at date: Date) {
        guard let fetched else { return }
        value = fetched
        fetchedAt = date
    }
}

extension DueInput where Value: Hashable & Codable {
    init(interval: TimeInterval, _ fetched: Fetched<Value>) {
        self.init(interval: interval, value: fetched.value, fetchedAt: fetched.fetchedAt)
    }

    /// The last good value with its fetch time, for the snapshot.
    var fetched: Fetched<Value>? {
        guard let value, let fetchedAt else { return nil }
        return Fetched(value, fetchedAt: fetchedAt)
    }
}
