import AuroraCore
import Foundation
import Synchronization
@testable import AlertServer

/// A store on a fresh temporary database file, removed after `body`.
func withTemporaryStore<T>(_ body: (RegistrationStore, String) async throws -> T) async throws -> T {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("alerts-\(UUID().uuidString).db").path
    let store = try await RegistrationStore.open(path: path)
    defer { try? FileManager.default.removeItem(atPath: path) }
    do {
        let result = try await body(store, path)
        try await store.close()
        return result
    } catch {
        try? await store.close()
        throw error
    }
}

/// Records pushes and answers from a script keyed by token (default: delivered).
final class FakePushSender: PushSender {
    private let state = Mutex<(sent: [PushRequest], results: [String: [PushResult]], defaultResult: PushResult)>(([], [:], .delivered))

    var sent: [PushRequest] { state.withLock { $0.sent } }

    /// Answers for `token`, one per send; the last one repeats.
    func respond(_ token: String, with results: PushResult...) {
        state.withLock { $0.results[token] = results }
    }

    func respondToAll(with result: PushResult) {
        state.withLock { $0.defaultResult = result }
    }

    func send(_ request: PushRequest) async -> PushResult {
        state.withLock { state in
            state.sent.append(request)
            guard var results = state.results[request.token], !results.isEmpty else { return state.defaultResult }
            let result = results.count > 1 ? results.removeFirst() : results[0]
            state.results[request.token] = results
            return result
        }
    }
}

/// Records heartbeat pings.
final class FakeHeartbeat: Heartbeat {
    private let pings = Mutex<[Bool]>([])

    var recorded: [Bool] { pings.withLock { $0 } }

    func ping(success: Bool) async {
        pings.withLock { $0.append(success) }
    }
}

/// A token for test number `n`: 32 bytes of lowercase hex.
func testToken(_ n: Int) -> String {
    let hex = String(n, radix: 16)
    return String(repeating: "0", count: 64 - hex.count) + hex
}

/// UTC date from "2026-11-03T20:00:00Z".
func utc(_ text: String) -> Date {
    try! Date(text, strategy: .iso8601)
}
