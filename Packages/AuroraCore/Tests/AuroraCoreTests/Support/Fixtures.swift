import Foundation

/// Access to recorded test data in `Tests/AuroraCoreTests/Fixtures/`.
enum Fixtures {
    static func url(_ name: String) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures")
    }

    static func data(_ name: String) throws -> Data {
        guard let url = url(name) else { throw FixtureError.missing(name) }
        return try Data(contentsOf: url)
    }

    static func exists(_ name: String) -> Bool {
        url(name) != nil
    }

    /// Name of the first fixture whose file name starts with `prefix`, e.g. "clouds-".
    static func first(prefix: String) -> String? {
        guard let dir = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return nil }
        return files.filter { $0.hasPrefix(prefix) }.sorted().first
    }

    enum FixtureError: Error {
        case missing(String)
    }
}

/// UTC date from an ISO 8601 string like "2026-10-22T16:23:10Z".
func utc(_ text: String) -> Date {
    try! Date(text, strategy: .iso8601)
}
