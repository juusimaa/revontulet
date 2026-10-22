/// Stores the last result between launches. The platform provides the storage (on iOS a file in
/// Application Support); the cache never leaves the device.
public protocol ResultCache: Sendable {
    func load() async -> AuroraResult?
    func save(_ result: AuroraResult) async
}

/// A cache that lives only as long as the process, for tests and previews.
public actor InMemoryResultCache: ResultCache {
    private var result: AuroraResult?

    public init(_ result: AuroraResult? = nil) {
        self.result = result
    }

    public func load() -> AuroraResult? {
        result
    }

    public func save(_ result: AuroraResult) {
        self.result = result
    }
}
