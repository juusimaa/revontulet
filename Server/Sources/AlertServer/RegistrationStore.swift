import AuroraCore
import Foundation
import SQLiteNIO

/// A stored registration: exactly the columns of `registrations` and nothing else (FR-013).
public struct Registration: Sendable, Equatable {
    public var token: String
    public var zone: String
    public var threshold: AlertThreshold
    /// Start of the UTC day of the last confirmation.
    public var confirmedAt: Date

    public init(token: String, zone: String, threshold: AlertThreshold, confirmedAt: Date) {
        self.token = token
        self.zone = zone
        self.threshold = threshold
        self.confirmedAt = confirmedAt
    }
}

public enum RegistrationStoreError: Error {
    case invalidRow
}

/// Registrations and per-zone alert state in SQLite (data-model.md). One connection, used
/// serially through the actor.
public actor RegistrationStore {
    private let connection: SQLiteConnection

    private init(connection: SQLiteConnection) {
        self.connection = connection
    }

    /// Opens (creating if needed) the database at `path`.
    public static func open(path: String) async throws -> RegistrationStore {
        let connection = try await SQLiteConnection.open(storage: .file(path: path))
        do {
            for statement in schema {
                _ = try await connection.query(statement)
            }
        } catch {
            try? await connection.close()
            throw error
        }
        return RegistrationStore(connection: connection)
    }

    private static let schema = [
        """
        CREATE TABLE IF NOT EXISTS registrations (
            token TEXT PRIMARY KEY,
            zone TEXT NOT NULL,
            threshold TEXT NOT NULL,
            confirmed_at INTEGER NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS registrations_zone ON registrations (zone)",
        "CREATE TABLE IF NOT EXISTS zone_alert_state (zone TEXT PRIMARY KEY, state TEXT NOT NULL)",
    ]

    public func close() async throws {
        try await connection.close()
    }

    // MARK: Registrations

    /// Creates or replaces the registration for the token, confirmed today.
    public func upsert(_ registration: RegistrationUpsert, now: Date) async throws {
        _ = try await connection.query(
            """
            INSERT INTO registrations (token, zone, threshold, confirmed_at) VALUES (?, ?, ?, ?)
            ON CONFLICT (token) DO UPDATE SET
                zone = excluded.zone, threshold = excluded.threshold, confirmed_at = excluded.confirmed_at
            """,
            [.text(registration.token), .text(registration.zone), .text(registration.threshold.rawValue),
             .integer(Self.startOfUTCDay(now))]
        )
    }

    public func delete(token: String) async throws {
        _ = try await connection.query("DELETE FROM registrations WHERE token = ?", [.text(token)])
    }

    public func registration(token: String) async throws -> Registration? {
        try await connection.query(
            "SELECT token, zone, threshold, confirmed_at FROM registrations WHERE token = ?", [.text(token)]
        ).first.map(Self.registration(from:))
    }

    public func registrations(inZone zone: String) async throws -> [Registration] {
        try await connection.query(
            "SELECT token, zone, threshold, confirmed_at FROM registrations WHERE zone = ?", [.text(zone)]
        ).map(Self.registration(from:))
    }

    /// Deletes registrations last confirmed before `date` (retention, FR-014); returns how many.
    @discardableResult
    public func deleteConfirmed(before date: Date) async throws -> Int {
        try await connection.query(
            "DELETE FROM registrations WHERE confirmed_at < ? RETURNING token",
            [.integer(Int(date.timeIntervalSince1970.rounded(.down)))]
        ).count
    }

    // MARK: Zone alert state

    /// The stored state of every zone, decoded from JSON.
    public func zoneStates<State: Decodable>(as type: State.Type) async throws -> [String: State] {
        let rows = try await connection.query("SELECT zone, state FROM zone_alert_state")
        var states: [String: State] = [:]
        for row in rows {
            guard let zone = row.column("zone")?.string, let json = row.column("state")?.string else {
                throw RegistrationStoreError.invalidRow
            }
            states[zone] = try JSONDecoder().decode(State.self, from: Data(json.utf8))
        }
        return states
    }

    public func saveZoneState<State: Encodable>(_ state: State, zone: String) async throws {
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        _ = try await connection.query(
            "INSERT INTO zone_alert_state (zone, state) VALUES (?, ?) ON CONFLICT (zone) DO UPDATE SET state = excluded.state",
            [.text(zone), .text(json)]
        )
    }

    // MARK: Helpers

    /// Column names of `table`, for checking that nothing else is stored.
    func columns(of table: String) async throws -> [String] {
        try await connection.query("SELECT name FROM pragma_table_info(?) ORDER BY cid", [.text(table)])
            .compactMap { $0.column("name")?.string }
    }

    /// Unix seconds of the start of the UTC day containing `date`, so the column cannot reveal
    /// when the app was opened.
    static func startOfUTCDay(_ date: Date) -> Int {
        let seconds = Int(date.timeIntervalSince1970.rounded(.down))
        return seconds - ((seconds % 86_400) + 86_400) % 86_400
    }

    private static func registration(from row: SQLiteRow) throws -> Registration {
        guard let token = row.column("token")?.string,
              let zone = row.column("zone")?.string,
              let threshold = row.column("threshold")?.string.flatMap(AlertThreshold.init(rawValue:)),
              let confirmedAt = row.column("confirmed_at")?.integer
        else { throw RegistrationStoreError.invalidRow }
        return Registration(token: token, zone: zone, threshold: threshold,
                            confirmedAt: Date(timeIntervalSince1970: TimeInterval(confirmedAt)))
    }
}
