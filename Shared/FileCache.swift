import AuroraCore
import Foundation

/// Keeps one value as a JSON file in the App Group container: the last result, or the last outlook
/// snapshot in a file of its own so an unreadable snapshot never affects the headline. Written
/// atomically, stays on the device and is excluded from backups (it is cheap to recreate).
struct FileCache<Value: Codable & Sendable>: Sendable {
    let fileURL: URL

    func load() async -> Value? {
        // A missing or unreadable file (e.g. after a format change) just means nothing cached.
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) async {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: fileURL, options: [.atomic])
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            // Not being able to cache only costs the instant result on the next launch.
        }
    }

    /// Removes the file, for UI tests that need a clean first launch.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

typealias FileResultCache = FileCache<AuroraResult>
typealias FileOutlookCache = FileCache<OutlookSnapshot>

extension FileCache: ResultCache where Value == AuroraResult {
    init() {
        self.init(fileURL: AppGroup.containerURL.appending(path: "last-result.json"))
    }
}

extension FileCache: OutlookCache where Value == OutlookSnapshot {
    init() {
        self.init(fileURL: AppGroup.containerURL.appending(path: "last-outlook.json"))
    }
}
