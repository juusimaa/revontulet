import Foundation
import Logging
import ServiceLifecycle

/// Once a night: deletes registrations the app has not re-confirmed for 180 days (FR-014), then
/// writes a backup that overwrites the previous one, so a deleted registration survives in a
/// backup for at most about a day (research R10).
public actor Maintenance: Service {
    static let retention: TimeInterval = 180 * 86_400
    /// 03:00 UTC (05:00 or 06:00 in Finland), after the night's alerts.
    static let runAt: TimeInterval = 3 * 3_600

    private let store: RegistrationStore
    private let backupPath: String
    private let logger: Logger

    public init(store: RegistrationStore, backupPath: String, logger: Logger = makeLogger()) {
        self.store = store
        self.backupPath = backupPath
        self.logger = logger
    }

    public func run() async throws {
        while !Task.isCancelled && !Task.isShuttingDownGracefully {
            let wait = Self.nextRun(after: Date()).timeIntervalSinceNow
            do {
                try await cancelWhenGracefulShutdown {
                    try await Task.sleep(for: .seconds(max(wait, 0)))
                }
            } catch {
                return
            }
            await runOnce(now: Date())
        }
    }

    /// The sweep and the backup; failures are logged and tried again the next night.
    func runOnce(now: Date) async {
        do {
            let deleted = try await sweep(now: now)
            logger.info("Retention sweep done", metadata: ["deleted": "\(deleted)"])
        } catch {
            logger.error("Retention sweep failed", metadata: ["error": "\(type(of: error))"])
        }
        do {
            try await backup()
        } catch {
            logger.error("Backup failed", metadata: ["error": "\(type(of: error))"])
        }
    }

    /// Deletes registrations last confirmed more than 180 days before today; returns how many.
    @discardableResult
    func sweep(now: Date) async throws -> Int {
        let today = Date(timeIntervalSince1970: TimeInterval(RegistrationStore.startOfUTCDay(now)))
        return try await store.deleteConfirmed(before: today.addingTimeInterval(-Self.retention))
    }

    func backup() async throws {
        try await store.backup(to: backupPath)
    }

    /// The first nightly run time strictly after `date`.
    static func nextRun(after date: Date) -> Date {
        let today = TimeInterval(RegistrationStore.startOfUTCDay(date))
        let run = Date(timeIntervalSince1970: today + runAt)
        return run > date ? run : run.addingTimeInterval(86_400)
    }
}
